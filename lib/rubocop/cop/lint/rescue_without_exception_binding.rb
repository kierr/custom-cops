# typed: false # RuboCop cop — T is undefined at load time
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `rescue StandardError` (or bare `rescue`) without binding the
      # exception variable (`=> e`), where the rescue body silently returns
      # nil/false with no logging or re-raise. This discards all errors
      # including programming errors (NoMethodError, TypeError, NameError) with
      # zero observability.
      #
      # The cop checks two conditions:
      # 1. The resbody has no exception variable binding (second child is nil).
      # 2. The body is nil, a literal (nil/false), or a simple return, and
      #    contains no logging calls (logger.error/warn/debug/info/fatal),
      #    Sentry calls, or re-raises.
      #
      # @example
      #
      #   # bad
      #   def perform
      #     result = risky_operation
      #     result
      #   rescue StandardError
      #     nil
      #   end
      #
      #   # bad — bare rescue is implicit StandardError
      #   def perform
      #     risky_operation
      #   rescue
      #     false
      #   end
      #
      #   # good — binds exception and logs it
      #   def perform
      #     result = risky_operation
      #     result
      #   rescue StandardError => e
      #     logger.error('perform_failed', error_class: e.class.name, error_message: e.message)
      #     nil
      #   end
      #
      #   # good — re-raises the exception
      #   rescue StandardError
      #     raise
      #   end
      #
      #   # good — logs via structured logging
      #   rescue StandardError
      #     logger.error('something_failed')
      #     nil
      #   end
      class RescueWithoutExceptionBinding < Base
        # NOTE: T::Sig/T::Boolean are unavailable at RuboCop load time; sig
        # annotations here are documentation-only and must not use T.* in method bodies.
        MSG = 'Rescue without exception binding silently discards errors. Bind the exception with `=> e` and log or re-raise it.'

        # Logging method names that indicate observability intent.
        LOG_METHODS = %i[error warn debug info fatal].freeze

        # Methods on Sentry/Raven that indicate error reporting.
        SENTRY_METHODS = %i[capture_exception capture_message].freeze

        # Exception types that are narrow enough to swallow silently (e.g.,
        # catching only NotFound is a legitimate nil-on-missing pattern).
        # StandardError and its broad subclasses are not narrow.
        NARROW_EXCEPTIONS = %i[ActiveRecord::RecordNotFound Net::ReadTimeout Net::OpenTimeout Errno::ECONNREFUSED Errno::ECONNRESET].freeze

        def on_resbody(node)
          return if binds_exception_variable?(node)
          return if body_has_logging?(node)
          return if body_has_sentry?(node)
          return if body_has_raise?(node)
          return if catches_narrow_exception?(node)

          add_offense(node.loc.keyword, message: MSG)
        end

        private

        # ResbodyNode children: [0] exception types, [1] variable binding (lvasgn or nil), [2] body
        def binds_exception_variable?(node)
          !node.children[1].nil?
        end

        def body_has_logging?(node)
          body = node.children[2]
          return false unless body

          body.each_node(:send).any? do |send_node|
            next false unless LOG_METHODS.include?(send_node.method_name)

            logging_receiver?(send_node.receiver)
          end
        end

        # True when receiver is a logger-like target: logger.error, @logger.error,
        # Rails.logger.error, etc.
        def logging_receiver?(receiver)
          return false unless receiver

          (receiver.send_type? && receiver.method_name == :logger) ||
            (receiver.ivar_type? && receiver.name == :@logger) ||
            (receiver.lvar_type? && receiver.name == :logger) ||
            rails_logger?(receiver)
        end

        # Rails.logger — two chained sends: (send (send nil :Rails) :logger)
        def rails_logger?(receiver)
          receiver.send_type? &&
            receiver.method_name == :logger &&
            receiver.receiver&.send_type? &&
            receiver.receiver.method_name == :Rails
        end

        def body_has_sentry?(node)
          body = node.children[2]
          return false unless body

          body.each_node(:send).any? do |send_node|
            next false unless SENTRY_METHODS.include?(send_node.method_name)

            receiver = send_node.receiver
            receiver && (
              (receiver.send_type? && %i[Sentry Raven].include?(receiver.method_name)) ||
                (receiver.const_type? && %i[Sentry Raven].include?(receiver.module_name))
            )
          end
        end

        def body_has_raise?(node)
          body = node.children[2]
          return false unless body

          body.each_node(:send).any? do |send_node|
            send_node.method_name == :raise && send_node.receiver.nil?
          end
        end

        def catches_narrow_exception?(node)
          exception_types = node.children[0]
          return false unless exception_types

          # Single specific exception that is not StandardError or RuntimeError
          types = if exception_types.array_type?
                    exception_types.children
                  else
                    [exception_types]
                  end

          return false if types.empty?
          return false if types.size > 1

          type_node = types.first
          return false unless type_node&.const_type?

          const_name = full_const_name(type_node)
          return false unless const_name

          # StandardError and RuntimeError are broad; everything else is narrow.
          # Compare directly to avoid Rails/NegateInclude (no ActiveSupport in RuboCop process).
          const_name != 'StandardError' && const_name != 'RuntimeError'
        end

        def full_const_name(node)
          return nil unless node&.const_type?

          # (const (const nil? :ActiveRecord) :RecordNotFound) => "ActiveRecord::RecordNotFound"
          # (const nil? :StandardError) => "StandardError"
          parts = []
          current = node
          iterations_const = 0
          while current&.const_type?
            iterations_const += 1
            break if iterations_const > 1_000

            parts.unshift(current.children[1].to_s)
            current = current.children[0]
          end
          parts.join('::')
        end
      end
    end
  end
end
