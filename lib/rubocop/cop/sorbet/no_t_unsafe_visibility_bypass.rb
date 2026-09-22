# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Sorbet
      # Flags `T.unsafe(self)` in before_action/callback contexts. `T.unsafe`
      # bypasses Sorbet's type checker only — it does not bypass Ruby's method
      # visibility. Private methods called via `T.unsafe(self).private_method`
      # still raise `NoMethodError`. Use `send(:method)` instead.
      #
      # @example
      #   # bad
      #   before_action -> { T.unsafe(self).set_current_user }
      #
      #   # good
      #   before_action -> { send(:set_current_user) }
      class NoTUnsafeVisibilityBypass < Base
        MSG = '`T.unsafe(self)` bypasses Sorbet only, not Ruby visibility. Use `send(:method_name)` for private methods in callbacks.'

        def_node_matcher :t_unsafe_self_in_block?, <<~PATTERN
          (send
            (const {nil? (cbase)} :T)
            :unsafe
            (self))
        PATTERN

        def on_send(node)
          return unless t_unsafe_self_in_block?(node)

          # Only flag when used in a block/lambda context (before_action, around_action, etc.)
          return unless in_callback_block?(node)

          add_offense(node.loc.expression, message: MSG)
        end

        private

        def in_callback_block?(node)
          parent = node.parent
          iterations_parent = 0
          while parent
            iterations_parent += 1
            break if iterations_parent > 1_000
            return true if parent.block_type? || parent.lambda_type?

            parent = parent.parent
          end
          false
        end
      end
    end
  end
end
