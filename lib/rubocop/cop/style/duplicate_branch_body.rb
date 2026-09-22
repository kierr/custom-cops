# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # Detects `if`/`else` branches where both bodies call the same method
      # with identical arguments. The duplicated logic should be collapsed into
      # a single branch with a combined condition (`if x || y`).
      #
      # Only flags two-branch `if`/`else` (no `elsif`). Requires exactly one
      # statement per branch, and that statement must be a method call with the
      # same receiver, method name, and arguments in both branches.
      #
      # @example
      #   # bad
      #   if x
      #     add_offense(node, message: MSG)
      #   else
      #     add_offense(node, message: MSG)
      #   end
      #
      #   # good — combine conditions
      #   if x || y
      #     add_offense(node, message: MSG)
      #   end
      #
      #   # good — branches differ
      #   if x
      #     add_offense(node, message: MSG_A)
      #   else
      #     add_offense(node, message: MSG_B)
      #   end
      class DuplicateBranchBody < Base
        MSG = 'Both branches have identical method calls. Combine conditions with `||` into a single branch.'

        # Only targets simple `if`/`else` — skips `elsif` chains and ternary.
        # Requires exactly one statement per branch, both being identical method calls.
        def on_if(node)
          return unless node.else_branch
          return if node.elsif?
          return if node.ternary?
          return if node.else_branch.if_type? # elsif is nested as else_branch if node

          true_body = single_statement(node.if_branch)
          false_body = single_statement(node.else_branch)
          return unless true_body && false_body
          return unless identical_send?(true_body, false_body)

          add_offense(node, message: MSG)
        end

        private

        # Returns the node if the branch is a single statement (not a begin block).
        # Returns nil for empty or multi-statement branches.
        def single_statement(branch)
          return nil unless branch

          branch.begin_type? ? nil : branch
        end

        # Two send nodes are identical when they share the same receiver,
        # method name, and all arguments.
        def identical_send?(node_a, node_b)
          return false unless node_a.send_type? && node_b.send_type?
          return false unless node_a.method_name == node_b.method_name
          return false unless node_a.receiver == node_b.receiver
          return false unless node_a.arguments == node_b.arguments

          true
        end
      end
    end
  end
end
