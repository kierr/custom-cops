# typed: true
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Detects rescue blocks with ad-hoc error logging and enforces consistent
      # format: structured keyword args with error_class, error_message, and
      # backtrace (before raise).
      #
      # The existing calls already produce correct SemanticLogger output — this
      # cop enforces uniformity, not a new pattern.
      #
      # Canonical format:
      #   Rails.logger.warn('name: rescued',
      #     error_class: e.class, error_message: e.message)
      #
      # With backtrace before raise:
      #   Rails.logger.error('name: rescued',
      #     error_class: e.class, error_message: e.message,
      #     backtrace: e.backtrace&.first(5))
      #   raise
      #
      # @example
      #
      #   # bad — missing error_class
      #   rescue StandardError => e
      #     logger.warn('operation failed', error_message: e.message)
      #
      #   # bad — missing error_message
      #   rescue StandardError => e
      #     logger.warn('operation: rescued', error_class: e.class)
      #
      #   # bad — string interpolation instead of structured fields
      #   rescue StandardError => e
      #     logger.error("Operation failed: #{e.class}: #{e.message}")
      #
      #   # bad — missing backtrace before raise
      #   rescue StandardError => e
      #     logger.error('operation: rescued',
      #       error_class: e.class, error_message: e.message)
      #     raise
      #
      #   # good
      #   rescue StandardError => e
      #     Rails.logger.warn('operation: rescued',
      #       error_class: e.class, error_message: e.message)
      #
      #   # good — with backtrace before raise
      #   rescue StandardError => e
      #     logger.error('consumer.error',
      #       error_class: e.class, error_message: e.message,
      #       backtrace: e.backtrace&.first(5))
      #     raise
      class ConsistentRescueLogging < Base
        extend AutoCorrector

        MSG_MISSING_FIELD = 'Rescue log call missing structured error field. Include error_class: and error_message: as keyword arguments.'
        MSG_STRING_INTERP = 'Rescue log uses string interpolation for error info. Use structured keyword arguments: error_class: e.class, error_message: e.message.'
        MSG_MISSING_BACKTRACE = 'Rescue log before bare raise should include backtrace: e.backtrace&.first(N) for unhandled error context.'

        LOG_METHODS = %i[warn error fatal].freeze

        def_node_search :rescue_blocks?, <<~PATTERN
          (resbody ...)
        PATTERN

        def on_resbody(node)
          # Find log calls within this rescue block
          log_calls = find_log_calls(node)
          return if log_calls.empty?

          # Check if this rescue re-raises
          re_raises = re_raises?(node)

          log_calls.each do |log_call|
            _ = check_log_call(log_call, re_raises)
          end
        end

        private

        def find_log_calls(resbody_node)
          calls = []
          return calls unless resbody_node.body

          # Walk every node type: log calls can sit inside if/unless/case
          # branches within the rescue body, not just at begin-block top level.
          walker = lambda do |node|
            calls << node if node.send_type? && logger_call?(node)
            node.children.each { |child| walker.call(child) if child.is_a?(::RuboCop::AST::Node) }
          end
          walker.call(resbody_node.body)
          calls
        end

        def logger_call?(node)
          return false unless LOG_METHODS.include?(node.method_name)
          return false unless node.receiver

          receiver = node.receiver
          case receiver.type
          when :send
            # Any chain terminating in `.logger` — covers bare `logger`,
            # `Rails.logger`, and `something.logger`. The previous
            # nil-receiver-only form made `Rails.logger.warn` (the canonical
            # format in this cop's docs) not matched.
            return true if receiver.method_name == :logger

            # The SemanticLogger['Name'] / SemanticLogger[self] idiom.
            receiver.method_name == :[] &&
              receiver.receiver&.const_type? &&
              receiver.receiver.short_name.to_s.end_with?('SemanticLogger')
          when :ivar
            receiver.name == :@logger
          when :lvar
            receiver.name == :logger
          when :const
            # LOGGER, LOG, etc.
            true
          else
            false
          end
        end

        def check_log_call(log_call, re_raises)
          first_arg = log_call.first_argument

          # Check for string interpolation (dstr) in the message
          # If the interpolation includes error info, flag it
          if first_arg&.dstr_type? && contains_error_info?(first_arg)
            add_offense(first_arg, message: MSG_STRING_INTERP) do |corrector|
              # Autocorrect: extract interpolated values into keyword args
              autocorrect_interpolation(corrector, log_call, first_arg)
            end
            return
          end

          # Check for missing structured fields
          keyword_args = extract_keyword_args(log_call)
          has_error_class = keyword_args.any? { |k, _| k == :error_class }
          has_error_message = keyword_args.key?(:error_message) || keyword_args.key?(:error)

          unless has_error_class && has_error_message
            add_offense(log_call, message: MSG_MISSING_FIELD)
            return
          end

          # Check for missing backtrace before raise
          return unless re_raises && !keyword_args.key?(:backtrace)

          add_offense(log_call, message: MSG_MISSING_BACKTRACE)
        end

        def contains_error_info?(dstr_node)
          source = dstr_node.source
          source.match?(/e\.(class|message|backtrace)/) ||
            source.match?(/exception\.(class|message|backtrace)/)
        end

        def extract_keyword_args(log_call)
          result = {}
          log_call.arguments.each do |arg|
            next unless arg.hash_type?

            arg.children.each do |pair|
              next unless pair.pair_type? || pair.kwarg_type?

              key_node = pair.children.first
              next unless key_node.sym_type?

              result[key_node.value] = pair.children.last
            end
          end
          result
        end

        def re_raises?(resbody_node)
          body = resbody_node.body
          return false unless body

          last_expr = if body.begin_type?
                        body.children.last
                      else
                        body
                      end

          last_expr&.send_type? && last_expr.method_name == :raise &&
            (last_expr.arguments.empty? || # bare raise
             last_expr.arguments.size == 1) # raise with no message
        end

        def autocorrect_interpolation(corrector, log_call, dstr_node)
          # Best-effort autocorrect for simple cases like:
          # "Error: #{e.class}: #{e.message}" → 'Error' with error_class: e.class, error_message: e.message
          parts = dstr_node.children.map do |child|
            if child.str_type?
              child.value
            elsif child.begin_type? && child.children.first
              inner = child.children.first
              if inner.send_type?
                case inner.method_name
                when :class then nil # will be extracted
                when :message then nil # will be extracted
                else "\#{#{inner.source}}"
                end
              else
                "\#{#{inner.source}}"
              end
            else
              ''
            end
          end

          message = parts.compact.join.gsub(/\s+$/, '').gsub(/:\s*$/, '')
          message = 'error' if message.empty?

          # Check if log_call already has keyword args
          has_kwargs = log_call.arguments.any?(&:hash_type?)

          replacement = if has_kwargs
                          "'#{message}'"
                        else
                          "'#{message}', error_class: e.class, error_message: e.message"
                        end

          corrector.replace(dstr_node, replacement)
        end
      end
    end
  end
end
