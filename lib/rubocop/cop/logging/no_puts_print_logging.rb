# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Bans `puts` and `print` as runtime logging in app/ and lib/.
      # Use `logger.info`, `logger.debug`, etc. instead.
      class NoPutsPrintLogging < Base
        MSG = 'Use logger.info/debug/warn/error instead of puts/print for runtime output.'

        def_node_matcher :puts_or_print?, <<~PATTERN
          (send nil? {:puts :print} ...)
        PATTERN

        def on_send(node)
          return unless puts_or_print?(node)

          add_offense(node)
        end
      end
    end
  end
end
