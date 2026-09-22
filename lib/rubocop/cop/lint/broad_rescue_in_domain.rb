# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `rescue StandardError` in domain service code where the rescue
      # body does not perform meaningful error handling. Only flags when the
      # rescue body lacks logging, re-raising, or error reporting — patterns
      # that silently swallow unexpected errors.
      #
      # Consumers and workers are excluded because broad error handling is
      # standard practice in Karafka consumer entry points. This cop targets
      # domain services where broad rescue is more likely a bug.
      #
      # @example
      #
      #   # bad — silently swallows all errors
      #   rescue StandardError => e
      #     nil
      #
      #   # good — logs or re-raises
      #   rescue StandardError => e
      #     logger.error('failed', error: e.message)
      #
      #   # good — re-raises
      #   rescue StandardError => e
      #     raise
      class BroadRescueInDomain < Base
        MSG = 'Narrow `rescue StandardError` to specific exception types, or add error handling (logging/re-raise).'

        def_node_matcher :broad_rescue?, <<~PATTERN
          (resbody (array (const {nil? (cbase)} :StandardError)) ...)
        PATTERN

        def on_resbody(node)
          return unless broad_rescue?(node)
          return if re_raises?(node)
          return unless in_domain_service?
          return if handles_error?(node)

          add_offense(node)
        end

        private

        def re_raises?(resbody_node)
          body = resbody_node.children[2]
          return false unless body

          case body.type
          when :send
            body.method_name == :raise && body.arguments.empty?
          when :begin
            body.children.last&.send_type? && body.children.last&.method_name == :raise && body.children.last&.arguments&.empty?
          else
            false
          end
        end

        def in_domain_service?
          path = processed_source.file_path
          path.include?('/app/services/') || path.include?('/lib/')
        end

        def handles_error?(resbody_node)
          body = resbody_node.children[2]
          return false unless body

          body.each_node(:send).any? do |send_node|
            name = send_node.method_name
            # Logging, error reporting, or re-raising counts as handling
            %i[error warn fatal info debug].include?(name) ||
              name.to_s.include?('sentry') ||
              name.to_s.include?('notify') ||
              name.to_s.include?('report') ||
              name.to_s.start_with?('track_') ||
              name.to_s.start_with?('record_') ||
              name == :raise
          end
        end
      end
    end
  end
end
