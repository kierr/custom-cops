# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `Timeout.timeout` usage in application code. Ruby's Timeout.timeout
      # is unsafe: it raises exceptions asynchronously via a separate thread, can
      # leave resources (file handles, DB connections, locks) in inconsistent state,
      # and does not guarantee cleanup in ensure blocks. The timeout thread can
      # interrupt at any point, including mid-expression.
      #
      # Use case-specific timeouts instead: HTTP client timeouts (Http.with(timeout:)),
      # IO.select with timeouts, or circuit breaker patterns.
      #
      # @example
      #
      #   # bad — asynchronous exception can corrupt state
      #   Timeout.timeout(30) { fetch_all_pages }
      #
      #   # bad — top-level ::Timeout
      #   ::Timeout.timeout(5) { dangerous_operation }
      #
      #   # good — HTTP client handles its own timeout
      #   Http.with(timeout: 30).get(url)
      #
      #   # good — IO.select with explicit timeout
      #   IO.select([socket], nil, nil, 5)
      class TimeoutTimeoutInApp < Base
        MSG = 'Avoid `Timeout.timeout` — it raises exceptions asynchronously and can leave resources in ' \
              'inconsistent state. Use HTTP client timeouts (Http.with(timeout:)), IO.select with timeouts, ' \
              'or circuit breaker patterns.'

        # Match `Timeout.timeout(...)` and `::Timeout.timeout(...)`
        def_node_matcher :timeout_timeout?, <<~PATTERN
          (send (const {nil? (cbase)} :Timeout) :timeout ...)
        PATTERN

        def on_send(node)
          return unless timeout_timeout?(node)

          add_offense(node.loc.selector)
        end
      end
    end
  end
end
