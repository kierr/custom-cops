# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects rescue blocks that log `e.message` without also logging `e.class`.
      # Dropping the error class from log output makes production debugging significantly
      # harder — the same message text can originate from multiple exception types, and
      # without the class the backtrace and error lineage are opaque.
      #
      # The codebase convention uses `error_class: e.class, error_message: e.message` in
      # structured log calls. This cop enforces that when `e.message` appears in a log call
      # within a rescue body, `e.class` is also present in the same or a sibling log call.
      #
      # Only flags log calls to known logger methods (debug/info/warn/error/fatal) on
      # recognized receivers: `logger`, `@logger`, `Rails.logger`, `LOGGER`, and
      # `SemanticLogger[...]`.
      #
      # @example
      #
      #   # bad — e.message without e.class
      #   rescue StandardError => e
      #     logger.error('operation failed', message: e.message)
      #
      #   # bad — e.message via keyword arg alias
      #   rescue StandardError => e
      #     SemanticLogger['Foo'].warn('failed', error: e.message)
      #
      #   # bad — e.message in string interpolation
      #   rescue StandardError => e
      #     logger.error("Operation failed: #{e.message}")
      #
      #   # good — both error_class and error_message present
      #   rescue StandardError => e
      #     logger.error('operation failed', error_class: e.class, error_message: e.message)
      #
      #   # good — e.class logged in a sibling call within same rescue body
      #   rescue StandardError => e
      #     logger.error('failed', error_class: e.class)
      #     logger.error('failed detail', error_message: e.message)
      #
      #   # good — e.message used but not in a log call (e.g. ServiceResult)
      #   rescue StandardError => e
      #     ServiceResult.failure(message: e.message)
      #
      class RescueLogsOnlyMessage < Base
        MSG = 'Log call includes `e.message` without `e.class` — add `error_class: %<var>s.class` to preserve the error type for debugging.'

        LOG_METHODS = %i[debug info warn error fatal].freeze

        # Keyword keys that carry the exception message in this codebase.
        MESSAGE_KEYWORDS = %i[error_message error message].freeze

        def on_resbody(node)
          exception_var = exception_variable_name(node)
          return unless exception_var
          return if rationale?(node)

          log_calls = find_log_calls(node)
          return if log_calls.empty?

          has_class = log_calls.any? { |call| references_class?(call, exception_var) }

          return if has_class

          log_calls.each do |call|
            next unless references_message?(call, exception_var)

            add_offense(call, message: format(MSG, var: exception_var))
          end
        end

        private

        # Per-instance escape hatch: a RATIONALE comment within 5 lines above
        # the rescue clause suppresses the offense. Legitimate when the error
        # class is captured elsewhere ( Sentry, metrics) or the call is not a
        # real logger despite matching the receiver shape.
        def rationale?(node)
          return false unless node.loc.expression

          node_line = node.loc.expression.line
          processed_source.comments.any? do |comment|
            comment_line = comment.loc.expression.line
            comment_line >= node_line - 5 && comment_line < node_line &&
              comment.text.include?('RATIONALE')
          end
        end

        # Extract the exception variable name from `rescue SomeError => var`.
        # Returns nil for bare rescue without a binding.
        def exception_variable_name(node)
          # resbody node structure: [exception_types, assignment, body]
          # assignment is an lvasgn node (local variable assignment) or nil.
          # Older RuboCop versions may use lvar; both carry a .name accessor.
          assignment = node.children[1]
          return nil unless assignment

          assignment.name if assignment.lvasgn_type? || assignment.lvar_type?
        end

        # Collect all logger method calls within the rescue body.
        def find_log_calls(node)
          body = node.children[2]
          return [] unless body

          calls = []

          walker = lambda do |n|
            case n.type
            when :send
              calls << n if logger_call?(n)
            when :begin
              n.children.each { |child| walker.call(child) }
            end
          end
          walker.call(body)
          calls
        end

        # Check whether a send node is a call to a logger method on a recognized receiver.
        def logger_call?(node)
          return false unless node.send_type?
          return false unless LOG_METHODS.include?(node.method_name)

          receiver = node.receiver
          return false unless receiver

          recognized_receiver?(receiver)
        end

        def recognized_receiver?(receiver)
          case receiver.type
          when :lvar
            receiver.name == :logger
          when :ivar
            receiver.name == :@logger
          when :const
            # A bare const receiver is a logger only by naming convention
            # (LOG, LOGGER, APP_LOGGER). Restrict to names whose final segment
            # is exactly log/logger so unrelated services exposing .error/.warn
            # (Notifier, Metrics, Blog) are not swept in.
            segment = receiver.const_name.to_s.split('::').last.to_s
            /(?:\A|_)log(?:ger)?\z/i.match?(segment)
          when :send
            send_logger_receiver?(receiver)
          else
            false
          end
        end

        # A send receiver qualifies as a logger when it is SemanticLogger[...],
        # a `.logger` accessor on a const (Rails.logger, App.logger), or a bare
        # `logger` parsed as (send nil? :logger).
        def send_logger_receiver?(receiver)
          if receiver.method_name == :[]
            receiver.receiver&.const_type? &&
              receiver.receiver&.source&.include?('SemanticLogger')
          elsif receiver.method_name == :logger
            receiver.receiver&.const_type? || receiver.receiver.nil?
          else
            false
          end
        end

        # Check whether the log call references <var>.class in any argument or keyword.
        def references_class?(call, var)
          call.each_descendant(:send).any? do |desc|
            desc.method_name == :class &&
              desc.receiver&.lvar_type? &&
              desc.receiver.name == var
          end
        end

        # Check whether the log call references <var>.message in any argument or keyword.
        # Covers keyword args (error_message/error/message), string interpolation, and bare
        # positional arguments.
        def references_message?(call, var)
          keyword_args = extract_keyword_args(call)
          message_kw = keyword_args.find do |key, value|
            MESSAGE_KEYWORDS.include?(key) &&
              send_access?(value, var, :message)
          end
          return true if message_kw

          call.arguments.each do |arg|
            next if arg.hash_type?

            return true if interpolation_references_var_message?(arg, var)
            return true if send_access?(arg, var, :message)
          end

          false
        end

        # Extract keyword arguments from a log call as an array of [symbol, node] pairs.
        def extract_keyword_args(call)
          result = []
          call.arguments.each do |arg|
            next unless arg.hash_type?

            arg.children.each do |pair|
              next unless pair.pair_type?

              key_node = pair.children.first
              next unless key_node.sym_type?

              result << [key_node.value, pair.children.last]
            end
          end
          result
        end

        # Check whether a node is `<var>.<method_name>` (e.g. `e.message`).
        def send_access?(node, var, method_name)
          return false unless node
          return false unless node.send_type?

          node.method_name == method_name &&
            node.receiver&.lvar_type? &&
            node.receiver.name == var
        end

        # Check whether a string interpolation node (dstr) references `<var>.message`.
        def interpolation_references_var_message?(node, var)
          return false unless node.dstr_type?

          node.each_descendant(:send).any? do |desc|
            desc.method_name == :message &&
              desc.receiver&.lvar_type? &&
              desc.receiver.name == var
          end
        end
      end
    end
  end
end
