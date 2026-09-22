# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Bans `Logger.new` and `require 'logger'` in app/ and lib/.
      # Use SemanticLogger instead.
      class NoStdlibLogger < Base
        MSG = 'Use SemanticLogger instead of stdlib Logger. Service classes may inherit `logger` via SemanticLogger::Loggable; other classes should `include SemanticLogger::Loggable` or use `SemanticLogger[\'ClassName\']`.'

        def_node_matcher :stdlib_logger_new?, <<~PATTERN
          (send (const {nil? (cbase)} :Logger) :new ...)
        PATTERN

        def_node_matcher :require_logger?, <<~PATTERN
          (send nil? :require (str "logger"))
        PATTERN

        def on_send(node)
          return unless stdlib_logger_new?(node) || require_logger?(node)

          add_offense(node)
        end
      end
    end
  end
end
