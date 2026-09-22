# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects bare `sleep N` calls where N is a magic number (integer or float
      # literal) rather than a named constant or calculated delay. Magic sleep
      # numbers encode rate-limit knowledge that should be named constants or
      # configuration values. When upstream changes rate limits, grep cannot
      # associate `sleep 21` with a specific service.
      #
      # The cop accepts `sleep` with constant references (`RATE_LIMIT_SLEEP`),
      # method calls (`calculate_backoff`), variables (`delay`), and arithmetic
      # on constants (`BASE_DELAY * 2`). Only bare integer and float literals
      # are flagged.
      #
      # @example
      #
      #   # bad — magic number encodes undocumented rate-limit knowledge
      #   sleep 21
      #   sleep 0.3
      #   Kernel.sleep(60)
      #
      #   # good — named constant communicates intent
      #   RATE_LIMIT_SLEEP = 21
      #   sleep RATE_LIMIT_SLEEP
      #
      #   # good — configuration value
      #   sleep config.fetch(:poll_interval)
      #
      #   # good — variable or method call
      #   sleep delay
      #   sleep calculate_backoff(attempt)
      #
      class SleepWithMagicNumber < Base
        MSG = 'Replace magic number in `sleep` with a named constant or configuration value to make rate-limit intent discoverable.'

        # Minimum sleep duration (in seconds) to flag. Defaults to 0 so all
        # magic-number sleeps are flagged. Set higher to ignore short pauses
        # (e.g., `MinimumSleepDuration: 1` skips `sleep 0.3`).
        def minimum_sleep_duration
          Float(cop_config.fetch('MinimumSleepDuration', 0))
        end

        def on_send(node)
          return unless sleep_call?(node)
          return unless single_numeric_literal_arg?(node)

          value = sleep_arg_value(node)
          return if value < minimum_sleep_duration

          add_offense(node.first_argument)
        end

        private

        # Match `sleep N`, `Kernel.sleep(N)`, `::Kernel.sleep(N)`, or
        # explicit-nil-receiver `nil.sleep(N)`. The latter is unlikely in
        # practice but covers the `send nil :sleep` form from the spec.
        def sleep_call?(node)
          return false unless node.method_name == :sleep

          receiver = node.receiver
          # No receiver (bare `sleep 21`) or explicit Kernel/nil receiver.
          receiver.nil? ||
            kernel_receiver?(receiver)
        end

        def kernel_receiver?(node)
          return true if node.nil_type?

          return false unless node.const_type?

          %w[Kernel ::Kernel].include?(node.source)
        end

        # The argument is a single integer or float literal — not a constant,
        # variable, method call, or arithmetic expression.
        def single_numeric_literal_arg?(node)
          args = node.arguments
          return false unless args.one?

          arg = args.first
          arg.int_type? || arg.float_type?
        end

        def sleep_arg_value(node)
          Float(node.first_argument.children[0])
        end
      end
    end
  end
end
