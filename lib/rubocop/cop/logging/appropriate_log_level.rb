# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Detects `logger.debug` calls inside `rescue` blocks for error conditions.
      # Error conditions should be logged at `warn` or `error` level so they are
      # visible in production. Debug-level logs are typically filtered out.
      #
      # Only flags when the log message contains error-related keywords.
      #
      # @example
      #
      #   # bad
      #   rescue StandardError => e
      #     logger.debug('html_scrape_consumer.payload_parse_error', error: e.message)
      #
      #   # good
      #   rescue StandardError => e
      #     logger.warn('html_scrape_consumer.payload_parse_error', error: e.message)
      class AppropriateLogLevel < Base
        MSG = 'Error conditions in rescue blocks should be logged at `warn` or `error` level, not `debug`.'

        ERROR_KEYWORDS = %w[error fail exception invalid parse_error timeout refused unauthorized forbidden].freeze

        def_node_matcher :debug_call?, <<~PATTERN
          (send {(send nil? :logger) (ivar :@logger) (lvar :logger) (const ... :LOGGER)} :debug ${str dstr} ...)
        PATTERN

        def on_send(node)
          msg_node = debug_call?(node)
          return unless msg_node
          return unless inside_rescue?(node)
          return unless error_related_message?(msg_node)

          add_offense(node.loc.selector)
        end

        private

        def inside_rescue?(node)
          node.each_ancestor(:resbody).any?
        end

        def error_related_message?(node)
          text = case node.type
                 when :str then node.value
                 when :dstr then node.children.map { |c| c.is_a?(String) ? c : c.source }
                                     .join
                 else node.source
                 end
          ERROR_KEYWORDS.any? { |kw| text.downcase.include?(kw) }
        end
      end
    end
  end
end
