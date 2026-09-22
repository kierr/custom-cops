# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Flags `Rails.logger` in domain code (services, jobs, models, lib).
      # Use `logger` (from SemanticLogger::Loggable) or `SemanticLogger['Name']` instead.
      # Allowed in config/, initializers, and framework glue.
      class NoRailsLoggerInDomainCode < Base
        MSG = 'Use `logger` (from SemanticLogger::Loggable) instead of Rails.logger in domain code. Service classes may inherit `logger`. Other classes: `include SemanticLogger::Loggable`. Modules/utilities: `SemanticLogger[\'Name\']`.'

        def_node_matcher :rails_logger?, <<~PATTERN
          (send (const {nil? (cbase)} :Rails) :logger)
        PATTERN

        def on_send(node)
          return unless rails_logger?(node)

          add_offense(node)
        end
      end
    end
  end
end
