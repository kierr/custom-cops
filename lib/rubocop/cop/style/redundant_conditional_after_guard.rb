# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # Detects a conditional that is redundant after a guard return with the same condition.
      # After `return unless expr`, expr is guaranteed true — a subsequent `if expr` is
      # tautological. After `return if expr`, expr is guaranteed false — a subsequent
      # `unless expr` is tautological.
      #
      # @example
      #   # bad
      #   return unless banned?(ip)
      #   if banned?(ip)
      #     raise "Banned"
      #   end
      #
      #   # good
      #   return unless banned?(ip)
      #   raise "Banned"
      class RedundantConditionalAfterGuard < Base
        MSG = 'This conditional is redundant — the preceding guard return already ensures this condition.'

        def on_if(node)
          return unless guard_return?(node)
          return unless (next_node = consecutive_sibling(node))
          return unless next_node.if_type?
          return if guard_return?(next_node)
          return unless same_condition_source?(node, next_node)
          return unless redundant_after_guard?(node, next_node)

          add_offense(next_node)
        end

        private

        # An if/unless where one branch is a return and the other is absent.
        def guard_return?(node)
          return false unless node.if_type?
          return false if node.elsif?

          then_is_return = node.body&.return_type?
          else_is_return = node.else_branch&.return_type?

          (then_is_return && !else_is_return) || (!then_is_return && else_is_return)
        end

        def consecutive_sibling(node)
          parent = node.parent
          return nil unless parent&.begin_type?

          siblings = parent.children
          idx = siblings.index(node)
          return nil unless idx && idx < siblings.size - 1

          siblings[idx + 1]
        end

        def same_condition_source?(guard_node, conditional_node)
          guard_node.condition&.source == conditional_node.condition&.source
        end

        # Use unless?/if? to determine guard sense, avoiding AST body/else mapping
        # inconsistencies between modifier and block form.
        def redundant_after_guard?(guard_node, conditional_node)
          if guard_node.unless?
            # return unless expr → expr is true after guard
            # Redundant if next conditional runs its body when expr is true
            # i.e., next is `if expr` (not unless)
            !conditional_node.unless?
          else
            # return if expr → expr is false after guard
            # Redundant if next conditional runs its body when expr is false
            # i.e., next is `unless expr`
            conditional_node.unless?
          end
        end
      end
    end
  end
end
