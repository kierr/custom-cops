# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `Array#shift` followed by a conditional return that discards the
      # shifted element. When `lines.shift` is chained with a match/check and the
      # next statement conditionally returns, the shifted line is consumed from the
      # array but never processed -- silent data loss with no error.
      #
      # The safe pattern is to check the element first (`lines.first`) and only
      # shift after the check passes, or to handle the nil/non-matching case
      # explicitly rather than returning silently.
      #
      # @example
      #
      #   # bad — shifted line is silently discarded when regex fails
      #   match = lines.shift&.match(REGEX)
      #   return unless match
      #
      #   # good — check first, shift only after validation
      #   line = lines.first
      #   match = line&.match(REGEX)
      #   return unless match
      #   lines.shift
      #
      #   # good — shifted value is used regardless of match result
      #   first_line = lines.shift
      #   process(first_line)
      #
      #   # good — no conditional return after shift
      #   header = lines.shift
      #   log("Skipped header: #{header}")
      class ArrayShiftBeforeMatchCheck < Base
        MSG = 'Array#shift before conditional return discards the shifted element silently. Check first with `first`, then shift after validation.'

        # Matches: var = <receiver>.shift&.<method>(...)
        def_node_matcher :shift_safe_nav_chained_check?, <<~PATTERN
          (lvasgn $_ (csend (send _ :shift) _ ...))
        PATTERN

        # Matches: var = <receiver>.shift.<method>(...)
        def_node_matcher :shift_regular_chained_check?, <<~PATTERN
          (lvasgn $_ (send (send _ :shift) _ ...))
        PATTERN

        def on_lvasgn(node)
          var_name = extract_shift_var(node)
          return unless var_name

          return unless (sibling = next_sibling(node))

          return_var = extract_conditional_return_var(sibling)
          return unless return_var

          # The conditional return must reference the same variable as the shift assignment.
          return unless var_name == return_var

          add_offense(node.loc.expression)
        end

        private

        # Extract the variable name from a shift+chained-check assignment.
        def extract_shift_var(node)
          shift_safe_nav_chained_check?(node) || shift_regular_chained_check?(node)
        end

        # Check if the sibling is a conditional return referencing a local variable.
        # Handles:
        #   return unless var  ->  (if (lvar :var) nil (return))
        #   return if var      ->  (if (lvar :var) (return) nil)
        #   return if !var     ->  (if (send (lvar :var) :!) nil (return))
        #
        # NOTE: NodePattern `nil` matches a nil-type AST node, but Ruby's `return
        # unless` produces a literal Ruby nil in the unused branch. Programmatic
        # check avoids this mismatch.
        def extract_conditional_return_var(node)
          return unless node.if_type?

          condition = node.condition
          true_branch = node.children[1]
          false_branch = node.children[2]

          # return unless var: condition is (lvar), true_branch is nil, false_branch is (return)
          return condition.name if condition.lvar_type? && true_branch.nil? && return_node?(false_branch)

          # return if var: condition is (lvar), true_branch is (return), false_branch is nil
          return condition.name if condition.lvar_type? && return_node?(true_branch) && false_branch.nil?

          # return if !var: condition is (send (lvar) :!), branches have return
          if condition.send_type? && condition.method_name == :! &&
             condition.receiver&.lvar_type?
            return condition.receiver.name if true_branch.nil? && return_node?(false_branch)
            return condition.receiver.name if return_node?(true_branch) && false_branch.nil?
          end

          nil

          def return_node?(node)
            node.is_a?(RuboCop::AST::Node) && node.return_type?
          end

          # Walk to the next sibling statement in the enclosing begin block.
          def next_sibling(node)
            parent = node.parent
            return unless parent&.begin_type?

            siblings = parent.children
            idx = siblings.index(node)
            return unless idx
            return unless idx + 1 < siblings.length

            siblings[idx + 1]
          end
        end
      end
    end
  end
end
