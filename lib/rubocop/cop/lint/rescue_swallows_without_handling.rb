# typed: strict
# frozen_string_literal: true

# All errors are 7018 "call on T.untyped" from RuboCop AST API
# (Parser::AST::Node methods — no RBI coverage).
module RuboCop
  module Cop
    module Lint
      # Detects `rescue` blocks that silently return nil without logging,
      # re-raising, or error tracking. Flags any rescue body (anywhere in app/)
      # where the last expression is `nil`, `return nil`, or `return` with no
      # preceding log/error/raise/ServiceResult/notify call.
      #
      # Complementary to BroadRescueInDomain (which targets services/lib) and
      # ConsumerRescueWithoutReraise / ConsumerEnsureSwallowsException (which
      # target Karafka consumers). This cop covers all app/ code.
      #
      # Consumers are excluded because ConsumerRescueWithoutReraise already
      # covers them with consumer-specific logic.
      #
      # A RATIONALE comment on the rescue line suppresses the offense — the
      # developer documents why silent swallowing is intentional.
      #
      # @example
      #
      #   # bad — silently swallows the exception
      #   def process(data)
      #     transform(data)
      #   rescue StandardError
      #     nil
      #   end
      #
      #   # bad — bare return returns nil implicitly
      #   rescue StandardError => e
      #     return
      #   end
      #
      #   # good — logs the error before returning nil
      #   rescue StandardError => e
      #     logger.error("processing failed", error: e.message)
      #     nil
      #   end
      #
      #   # good — re-raises
      #   rescue StandardError => e
      #     raise
      #   end
      #
      #   # good — returns a typed failure
      #   rescue StandardError => e
      #     ServiceResult.failure(e.message)
      #   end
      #
      #   # good — RATIONALE suppresses the offense
      #   rescue StandardError # RATIONALE: polling — nil signals "no data yet"
      #     nil
      #   end
      class RescueSwallowsWithoutHandling < Base
        MSG = 'Rescue block returns nil without logging, re-raising, or error tracking. Add error handling or a RATIONALE comment.'

        # Logging method names that indicate error-aware rescue bodies.
        LOG_METHODS = %i[error warn fatal info debug].freeze

        # Method names that indicate proper error handling (reporting/tracking).
        HANDLING_METHODS = %i[raise fail notify capture report].freeze

        # Method name substrings that indicate error reporting tools.
        HANDLING_PATTERNS = %w[sentry notify report track_ record_].freeze

        # Const receiver names for error reporting tools — any method call on these counts.
        ERROR_REPORTING_CONSTS = %w[Sentry Bugsnag Honeybadger Airbrake Rollbar NewRelic].freeze

        # Method names indicating typed failure returns.
        FAILURE_RESULT_METHODS = %i[failure err].freeze

        # Classes whose rescue bodies are handled by consumer-specific cops.
        CONSUMER_SUPERCLASSES = %w[ApplicationConsumer Base].freeze

        # Node types whose children may contain error-handling calls.
        # :block — e.g., logger.error { "msg" }
        # :begin — multi-statement body
        # :if — conditional handling
        # :return — return ServiceResult.failure(...)
        CONTAINER_TYPES = %i[block begin if return].freeze

        # Logging receiver method names for send-type receivers (e.g., logger.error).
        LOGGING_SEND_RECEIVERS = %i[logger log].freeze

        # Logging receiver variable names for ivar/lvar receivers (e.g., @logger.error).
        LOGGING_VAR_RECEIVERS = %i[@logger @log logger log].freeze

        # Logging receiver const names — uppercase logger constants (e.g., LOGGER.debug).
        LOGGING_CONST_RECEIVERS = %w[LOGGER LOG SemanticLogger].freeze

        def on_resbody(node)
          return if in_consumer?(node)
          return if has_rationale_comment?(node)
          return if body_handles_error?(node)
          return unless last_expression_swallows?(node)

          add_offense(node.loc.keyword, message: MSG)
        end

        private

        # Returns the body of a resbody node.
        # resbody structure: (resbody <exception-list> <variable> <body>)
        def resbody_body(node)
          node.children[2]
        end

        # Returns the last meaningful expression from a rescue body.
        def last_expression(body)
          return nil unless body

          body.begin_type? ? body.children.last : body
        end

        # Whether the last expression in the rescue body is a silent nil return.
        # Matches: bare `nil`, `return nil`, `return` (implicit nil), empty body.
        def last_expression_swallows?(node)
          body = resbody_body(node)
          return true unless body # empty rescue body

          last = last_expression(body)
          return false unless last

          nil_return?(last)
        end

        # Returns true for nil literal, `return nil`, or bare `return`.
        def nil_return?(node)
          return true if node.nil_type?
          return false unless node.return_type?

          children = node.children
          children.empty? || (children.size == 1 && children.first.nil_type?)
        end

        # Whether the rescue body contains any error-handling calls.
        def body_handles_error?(node)
          body = resbody_body(node)
          return false unless body

          handles_error_in?(body)
        end

        # Recursively checks whether a node tree contains error-handling calls.
        def handles_error_in?(node)
          return false unless node

          if node.send_type?
            handling_send?(node)
          elsif CONTAINER_TYPES.include?(node.type)
            node.children.any? { |c| c.is_a?(Parser::AST::Node) && handles_error_in?(c) }
          else
            false
          end
        end

        # Validates that a send node is a legitimate error-handling call with
        # proper receiver context. Delegates to focused predicate methods to
        # keep cyclomatic complexity within limits.
        def handling_send?(node)
          return false unless node.send_type?

          method_name = node.method_name

          unconditional_handling?(method_name) ||
            (LOG_METHODS.include?(method_name) && valid_logging_receiver?(node)) ||
            failure_result_send?(node) ||
            pattern_handling?(method_name) ||
            error_reporting_const?(node)
        end

        # Methods that count as handling regardless of receiver.
        def unconditional_handling?(method_name)
          HANDLING_METHODS.include?(method_name)
        end

        # Method names containing error-reporting substrings.
        def pattern_handling?(method_name)
          name_str = method_name.to_s
          HANDLING_PATTERNS.any? { |pat| name_str.include?(pat) }
        end

        # Calls on known error-reporting constants (Sentry.capture_exception, etc.)
        def error_reporting_const?(node)
          receiver = node.receiver
          receiver&.const_type? && ERROR_REPORTING_CONSTS.any? { |c| receiver.const_name&.include?(c) }
        end

        # Validates receiver for log method calls. Avoids false positives from
        # unrelated methods named `error`, `warn`, `info`, `debug`.
        def valid_logging_receiver?(node)
          receiver = node.receiver
          return false unless receiver

          const_logging_receiver?(receiver) ||
            send_logging_receiver?(receiver) ||
            var_logging_receiver?(receiver)
        end

        # Const receivers: LOGGER.debug, LOG.warn, SemanticLogger.error
        # Also Rails.logger.error (send with const parent) and
        # SemanticLogger["Foo"].warn (indexing a const creates a child logger).
        def const_logging_receiver?(receiver)
          return true if receiver.const_type? && LOGGING_CONST_RECEIVERS.include?(receiver.const_name)
          return false unless receiver.send_type? && receiver.receiver&.const_type?

          receiver.method_name == :logger ||
            LOGGING_CONST_RECEIVERS.include?(receiver.receiver.const_name)
        end

        # Method-call receivers: logger.error, log.error
        def send_logging_receiver?(receiver)
          receiver.send_type? && LOGGING_SEND_RECEIVERS.include?(receiver.method_name)
        end

        # Variable receivers: @logger.error, @log.error, logger (lvar), log (lvar)
        def var_logging_receiver?(receiver)
          return false unless receiver.ivar_type? || receiver.lvar_type?

          LOGGING_VAR_RECEIVERS.include?(receiver.name)
        end

        # Matches ServiceResult.failure(...) and ServiceResult.err(...).
        def failure_result_send?(node)
          return false unless FAILURE_RESULT_METHODS.include?(node.method_name)

          receiver = node.receiver
          return false unless receiver&.const_type?

          %w[ServiceResult Result Failure].any? { |prefix| receiver.const_name&.include?(prefix) }
        end

        # Whether the rescue node has a RATIONALE comment on the rescue line.
        # Comments are attached to the processed source, not the AST node, so
        # we check comment positions relative to the rescue keyword.
        def has_rationale_comment?(node)
          comments = processed_source.comments
          rescue_line = node.loc.keyword.line

          comments.any? do |comment|
            comment.loc.line == rescue_line && comment.text.include?('RATIONALE:')
          end
        end

        # Whether the rescue node is inside a Karafka consumer class.
        def in_consumer?(node)
          class_parent = node.each_ancestor(:class).first
          return false unless class_parent

          parent_class = class_parent.parent_class
          return false unless parent_class

          CONSUMER_SUPERCLASSES.include?(parent_class.const_name)
        end
      end
    end
  end
end
