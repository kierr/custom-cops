# typed: strict
# frozen_string_literal: true

# All errors are 7018 "call on T.untyped" from RuboCop AST API
# (Parser::AST::Node methods — no RBI coverage).
module RuboCop
  module Cop
    module Lint
      # Detects `rescue StandardError` blocks with zero observable error handling:
      # no logging, no re-raise, no error tracking, and no ServiceResult.
      #
      # A rescue block that catches StandardError and does nothing observable with
      # the error silently swallows programming bugs (NoMethodError, TypeError,
      # NameError) along with expected failures. Every rescue StandardError must
      # demonstrate at least one of:
      #
      # 1. A log call on a recognized receiver (logger, @logger, Rails.logger, LOGGER,
      #    LOG, SemanticLogger)
      # 2. A `raise` or `fail` call (re-raise)
      # 3. Sentry/Raven/NewRelic/notify/report error tracking
      # 4. `ServiceResult.failure` or `ServiceResult.error`
      # 5. `error_class:` or `error_message:` keyword arguments (structured context)
      #
      # Narrow exception types (anything except StandardError and RuntimeError) are
      # excluded — rescuing only `ActiveRecord::RecordNotFound` is a legitimate
      # nil-on-missing pattern.
      #
      # Methods named `health_check` or containing `health_check` are excluded —
      # these endpoints use rescue-returns to signal health status, and the caller
      # provides observability.
      #
      # A RATIONALE comment at the rescue site suppresses this cop.
      #
      # @example
      #
      #   # bad — silently swallows all StandardError
      #   def perform
      #     risky_operation
      #   rescue StandardError
      #     nil
      #   end
      #
      #   # bad — does something but nothing observably handles the error
      #   def perform
      #     risky_operation
      #   rescue StandardError
      #     cleanup_resources
      #     nil
      #   end
      #
      #   # good — logs the error
      #   rescue StandardError => e
      #     logger.error('perform_failed', error_class: e.class, error_message: e.message)
      #     nil
      #   end
      #
      #   # good — re-raises
      #   rescue StandardError
      #     raise
      #   end
      #
      #   # good — ServiceResult
      #   rescue StandardError => e
      #     ServiceResult.failure(message: e.message)
      #   end
      #
      #   # good — RATIONALE suppression
      #   rescue StandardError # RATIONALE: intentional nil-on-failure for cache miss
      #     nil
      #   end
      #
      #   # good — narrow exception type
      #   rescue ActiveRecord::RecordNotFound
      #     nil
      #   end
      class SilentRescueNoTrackNoRaise < Base
        MSG = 'Rescue StandardError with no observable error handling. ' \
              'Add logging, re-raise, error tracking, or ServiceResult, or suppress with RATIONALE.'

        # Logging method names that indicate observability.
        LOG_METHODS = %i[debug info warn error fatal].freeze

        # Receivers whose <method> calls constitute logging.
        LOG_RECEIVER_NAMES = %i[logger LOGGER LOG].freeze

        # Sentry/Raven error tracking methods.
        TRACKING_METHODS = %i[capture_exception capture_message capture].freeze
        TRACKING_RECEIVERS = %i[Sentry Raven].freeze

        # NewRelic/notify/report methods that indicate error observability.
        REPORT_METHODS = %i[notify report notice].freeze
        REPORT_RECEIVERS = %i[NewRelic Airbrake Bugsnag Honeybadrier Rollbar].freeze

        # ServiceResult methods that indicate the error is surfaced.
        SERVICE_RESULT_METHODS = %i[failure error].freeze

        # Keyword argument keys that indicate structured error context.
        ERROR_CONTEXT_KEYWORDS = %i[error_class error_message].freeze

        # Methods where rescue-returns are legitimate health-signal patterns.
        EXCLUDED_METHOD_NAMES = %i[health_check healthcheck ok? healthy? alive? ready?].freeze

        # Broad exception types that indicate catch-all intent.
        BROAD_EXCEPTION_TYPES = %w[StandardError RuntimeError].freeze

        # Node types whose children should be walked recursively for observability.
        RECURSIVE_BODY_TYPES = %i[begin kwbegin rescue resbody pair hash].freeze

        def on_resbody(node)
          return unless catches_broad_exception?(node)
          return if excluded_method?(node)
          return if rationale_comment_present?(node)
          return if body_has_observable_handling?(node)

          add_offense(node.loc.keyword, message: MSG)
        end

        private

        # Returns true when the resbody catches StandardError, RuntimeError, or is
        # a bare rescue (implicit StandardError). Narrow types are excluded.
        def catches_broad_exception?(node)
          exception_list = node.children[0]
          # Bare rescue: (resbody nil ...) — implicit StandardError.
          return true if exception_list.nil?

          types = if exception_list.array_type?
                    exception_list.children
                  else
                    [exception_list]
                  end

          return false if types.empty?

          types.any? do |type_node|
            next false unless type_node&.const_type?

            BROAD_EXCEPTION_TYPES.include?(full_const_name(type_node))
          end
        end

        # Exclude health-check-like methods where rescue-returns signal health.
        def excluded_method?(node)
          def_node = node.each_ancestor(:def, :defs).first
          return false unless def_node

          EXCLUDED_METHOD_NAMES.include?(def_node.method_name)
        end

        # A RATIONALE comment on or immediately before the rescue line suppresses.
        def rationale_comment_present?(node)
          comments = processed_source.comments
          rescue_line = node.loc.keyword.line

          comments.any? do |comment|
            comment_line = comment.loc.line
            on_or_above = comment_line == rescue_line || comment_line == rescue_line - 1
            on_or_above && comment.text.include?('RATIONALE')
          end
        end

        # Central check: does the rescue body contain any observable error handling?
        def body_has_observable_handling?(node)
          body = node.children[2]
          return false unless body

          walk_for_observability(body)
        end

        # Walk the rescue body looking for any observable error-handling pattern.
        def walk_for_observability(node)
          return false unless node

          if RECURSIVE_BODY_TYPES.include?(node.type)
            return node.children.any? do |child|
              child.is_a?(Parser::AST::Node) && walk_for_observability(child)
            end
          end

          case node.type
          when :send
            observable_send?(node)
          when :block
            walk_block_for_observability(node)
          when :if
            node.children.compact.any? { |child| walk_for_observability(child) }
          else
            false
          end
        end

        # Check both the method call and block body for observability.
        def walk_block_for_observability(node)
          send_node = node.children.first
          block_body = node.children[2]
          observable_send?(send_node) || (block_body && walk_for_observability(block_body))
        end

        # Checks a single send node for any observable error-handling pattern.
        def observable_send?(node)
          return false unless node&.send_type?

          method_name = node.method_name
          receiver = node.receiver

          re_raise?(method_name, receiver) ||
            log_call?(method_name, receiver) ||
            tracking_call?(method_name, receiver) ||
            report_call?(method_name, receiver) ||
            service_result_call?(method_name, receiver) ||
            has_error_context_keywords?(node)
        end

        def re_raise?(method_name, receiver)
          %i[raise fail].include?(method_name) && receiver.nil?
        end

        def log_call?(method_name, receiver)
          LOG_METHODS.include?(method_name) && logging_receiver?(receiver)
        end

        def tracking_call?(method_name, receiver)
          TRACKING_METHODS.include?(method_name) && tracking_receiver?(receiver)
        end

        def report_call?(method_name, receiver)
          REPORT_METHODS.include?(method_name) && report_receiver?(receiver)
        end

        def service_result_call?(method_name, receiver)
          SERVICE_RESULT_METHODS.include?(method_name) && service_result_receiver?(receiver)
        end

        # Recognized logging receivers: logger, @logger, Rails.logger, LOGGER, LOG,
        # SemanticLogger['Class'].
        def logging_receiver?(receiver)
          return false unless receiver

          case receiver.type
          when :lvar
            LOG_RECEIVER_NAMES.include?(receiver.name)
          when :ivar
            receiver.name == :@logger
          when :const
            const_name = receiver.children[1]
            LOG_RECEIVER_NAMES.include?(const_name) || const_name == :Rails
          when :send
            logging_send_receiver?(receiver)
          else
            false
          end
        end

        # Handles the :send branch of logging_receiver? — extracted to reduce complexity.
        # Recurses into the inner receiver for chained access patterns.
        def logging_send_receiver?(receiver)
          # Bare `logger` parsed as (send nil :logger).
          return true if bare_logger?(receiver)
          # Rails.logger — (send (send nil :Rails) :logger)
          return true if rails_logger?(receiver)
          # SemanticLogger['Class'] — (send (const nil? :SemanticLogger) :[])
          return true if semantic_logger?(receiver)

          # For chained send nodes (e.g., foo.bar.logger), recurse on the inner receiver.
          inner = receiver.receiver
          return false unless inner

          logging_receiver?(inner)
        end

        def bare_logger?(receiver)
          receiver.method_name == :logger && receiver.receiver.nil?
        end

        def rails_logger?(receiver)
          receiver.method_name == :logger &&
            receiver.receiver&.send_type? &&
            receiver.receiver.method_name == :Rails
        end

        def semantic_logger?(receiver)
          receiver.method_name == :[] &&
            receiver.receiver&.const_type? &&
            receiver.receiver&.source&.include?('SemanticLogger')
        end

        # Sentry/Raven receiver check.
        def tracking_receiver?(receiver)
          return false unless receiver

          case receiver.type
          when :const
            TRACKING_RECEIVERS.include?(receiver.const_name.to_sym)
          when :send
            TRACKING_RECEIVERS.include?(receiver.method_name) if receiver.receiver.nil?
          else
            false
          end
        end

        # NewRelic/Airbrake receiver check — matches const names and nested modules.
        def report_receiver?(receiver)
          return false unless receiver

          if receiver.const_type?
            REPORT_RECEIVERS.include?(receiver.const_name.to_sym) ||
              const_chain_includes?(receiver, REPORT_RECEIVERS)
          elsif receiver.send_type?
            report_receiver?(receiver.receiver) if receiver.receiver
          else
            false
          end
        end

        # ServiceResult.failure / ServiceResult.error — const receiver named ServiceResult.
        def service_result_receiver?(receiver)
          return false unless receiver
          return false unless receiver.const_type?

          receiver.const_name == 'ServiceResult' || receiver.source == 'ServiceResult'
        end

        # Check keyword arguments for error_class: or error_message: keys.
        def has_error_context_keywords?(node)
          node.arguments.each do |arg|
            next unless arg.hash_type?

            arg.children.each do |pair|
              next unless pair.pair_type?

              key_node = pair.children.first
              next unless key_node.sym_type?

              return true if ERROR_CONTEXT_KEYWORDS.include?(key_node.value)
            end
          end
          false
        end

        # Returns the full constant name from a const node.
        def full_const_name(node)
          return nil unless node&.const_type?

          parts = []
          current = node
          iterations = 0
          while current&.const_type?
            iterations += 1
            break if iterations > 1_000

            parts.unshift(current.children[1].to_s)
            current = current.children[0]
          end
          parts.join('::')
        end

        # Check whether any const in the chain matches one of the given names.
        def const_chain_includes?(node, names)
          current = node
          iterations = 0
          while current&.const_type?
            iterations += 1
            break if iterations > 1_000

            return true if names.include?(current.const_name.to_sym)

            current = current.children[0]
          end
          false
        end
      end
    end
  end
end
