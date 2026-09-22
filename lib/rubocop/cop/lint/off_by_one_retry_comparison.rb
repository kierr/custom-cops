# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects retry/attempts counter comparisons that use `>=` or `==`
      # against a variable or constant whose name contains "max_retries",
      # "max_attempts", "retry_limit", or "attempt_limit".
      #
      # When retrying up to N times, attempts go 0, 1, 2, ... N. The correct
      # stop condition is `attempts > max_retries` (strictly greater than),
      # which allows exactly N+1 evaluations (0 through N) and stops before
      # attempt N+1. Using `>=` permits one extra retry beyond the intended
      # maximum. Using `==` can miss the condition if the counter is
      # incremented concurrently and skips the exact equality value.
      #
      # @example
      #
      #   # bad — allows one extra retry
      #   break if attempts >= max_retries
      #
      #   # bad — misses condition if attempts skips the value
      #   break if attempts == max_retries
      #
      #   # good — stops at exactly N retries
      #   break if attempts > max_retries
      #
      class OffByOneRetryComparison < Base
        MSG = '`%<op>s max_retries` is an off-by-one retry comparison. Use `>` to stop at exactly N retries.'

        COMPARISON_OPS = %i[>= ==].freeze
        # Stem patterns that match both singular and plural forms.
        RETRY_STEMS = %w[retr attempt].freeze
        LIMIT_STEMS = %w[max limit].freeze

        def_node_matcher :comparison_with_retry_variable?, <<~PATTERN
          (send _ {#{COMPARISON_OPS.map(&:inspect).join(' ')}} _)
        PATTERN

        def on_send(node)
          return unless comparison_with_retry_variable?(node)

          left, op, right = extract_comparison_parts(node)
          return unless COMPARISON_OPS.include?(op)
          return unless retry_limit_name?(left) || retry_limit_name?(right)

          add_offense(node, message: format(MSG, op: op))
        end

        private

        def extract_comparison_parts(node)
          [node.receiver, node.method_name, node.arguments.first]
        end

        def retry_limit_name?(node)
          name = variable_name(node)
          return false unless name

          downcased = name.downcase
          has_retry = RETRY_STEMS.any? { |stem| downcased.include?(stem) }
          has_limit = LIMIT_STEMS.any? { |stem| downcased.include?(stem) }

          has_retry && has_limit
        end

        def variable_name(node)
          case node.type
          when :lvar, :ivar, :cvar
            node.children[0].to_s
          when :gvar
            # Global variables include the $ prefix — strip it for name matching.
            node.children[0].to_s.delete_prefix('$')
          when :const
            node.children[1].to_s
          when :send
            # Handles cases like `self.max_retries` or `config.retry_limit`.
            node.method_name.to_s
          end
        end
      end
    end
  end
end
