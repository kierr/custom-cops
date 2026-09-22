# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Flags `extend SemanticLogger::Loggable` which raises `NoMethodError`.
      # Use `include SemanticLogger::Loggable` or `LOGGER = SemanticLogger['Name']` instead.
      # AR models, jobs, and controllers already inherit a `logger` method.
      #
      # @example
      #   # bad
      #   extend SemanticLogger::Loggable
      #
      #   # good
      #   include SemanticLogger::Loggable
      #   LOGGER = SemanticLogger['MyClass']
      class NoExtendLoggable < Base
        MSG = 'Use `include SemanticLogger::Loggable` or `LOGGER = SemanticLogger[\'Name\']` instead of `extend`. AR models/jobs/controllers already inherit `logger`.'

        def_node_matcher :extend_semantic_logger?, <<~PATTERN
          (send nil? :extend (const (const nil? :SemanticLogger) :Loggable))
        PATTERN

        def on_send(node)
          return unless extend_semantic_logger?(node)

          add_offense(node.loc.selector, message: MSG)
        end
      end
    end
  end
end
