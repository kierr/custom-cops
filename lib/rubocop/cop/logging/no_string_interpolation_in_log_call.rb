# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Detects string-interpolated logger calls, which prevent structured log
      # aggregation and alerting. Use SemanticLogger keyword arguments instead
      # of embedding interpolated values into the message string.
      #
      # Interpolated strings (dstr nodes) embed runtime values directly into the
      # log message text, making it impossible to aggregate, search, or alert on
      # individual fields. SemanticLogger's keyword-argument form stores each
      # value as a separate structured field.
      #
      # @example
      #
      #   # bad
      #   logger.error("AGE traverse failed: #{e.class}: #{e.message}")
      #   LOGGER.info("User #{user.id} signed in from #{request.ip}")
      #   @logger.warn("Retrying #{attempt} of #{max}: #{reason}")
      #
      #   # good
      #   logger.error('AGE traverse failed', error_class: e.class.name, error_message: e.message)
      #   LOGGER.info('User signed in', user_id: user.id, ip: request.ip)
      #   @logger.warn('Retrying', attempt: attempt, max: max, reason: reason)
      #
      #   # good — plain string without interpolation
      #   logger.info('Processing started')
      #
      #   # good — structured log call with keyword arguments
      #   logger.error('sync.failed', account_id: account.id)
      class NoStringInterpolationInLogCall < Base
        MSG = 'Avoid string interpolation in log calls. Use SemanticLogger keyword arguments for structured fields.'

        LOG_METHODS = %i[debug info warn error fatal].freeze

        # Match logger receivers: bare logger() call, @logger ivar, logger lvar, LOGGER constant.
        # The const pattern matches any constant-named logger (LOGGER, SemanticLogger::Logger, etc).
        def_node_matcher :log_call_with_dstr?, <<~PATTERN
          (send {(send nil? :logger) (ivar :@logger) (lvar :logger) (const ...)} LOG_METHODS $(dstr ...) ...)
        PATTERN

        def on_send(node)
          return unless LOG_METHODS.include?(node.method_name)
          return unless logger_receiver?(node)

          first_arg = node.first_argument
          return unless first_arg
          return unless first_arg.dstr_type?

          add_offense(first_arg)
        end

        private

        # Verify the receiver is a known logger form. Defensive check beyond the
        # def_node_matcher to avoid false positives on arbitrary method chains.
        def logger_receiver?(node)
          receiver = node.receiver
          return false unless receiver

          case receiver.type
          when :send
            receiver.send_type? && receiver.method_name == :logger
          when :ivar
            receiver.ivar_type? && receiver.name == :@logger
          when :lvar
            receiver.lvar_type? && receiver.name == :logger
          when :const
            true
          else
            false
          end
        end
      end
    end
  end
end
