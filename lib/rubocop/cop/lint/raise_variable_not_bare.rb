# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `raise <variable>` inside a rescue block where the variable was bound by
      # the enclosing `rescue =>` clause. Bare `raise` preserves the original backtrace;
      # `raise e` creates a new backtrace starting at the re-raise site, losing the fault
      # origin. This cop enforces the bare form for consistency.
      #
      # Only flags re-raises of the *exact* rescue variable. `raise SomeOtherError` and
      # `raise e.new_message` are not flagged — those construct new exceptions intentionally.
      #
      # @example
      #
      #   # bad
      #   rescue StandardError => e
      #     logger.error e.message
      #     raise e
      #
      #   # good
      #   rescue StandardError => e
      #     logger.error e.message
      #     raise
      class RaiseVariableNotBare < Base
        extend AutoCorrector

        MSG = 'Use bare `raise` instead of `raise %<var>s` to preserve the original backtrace.'

        # Match `raise <lvar>` and `Kernel.raise <lvar>` / `::Kernel.raise <lvar>` —
        # the Kernel-receiver form is functionally identical and previously evaded
        # the matcher (error-handling-multipass: 8 consumer sites used it).
        def_node_matcher :raise_lvar?, <<~PATTERN
          (send {nil? (const {nil? cbase} :Kernel)} :raise (lvar _))
        PATTERN

        def on_send(node)
          return unless raise_lvar?(node)

          raised_var_name = node.first_argument.children.first
          return unless enclosed_rescue_binds?(node, raised_var_name)

          add_offense(node, message: format(MSG, var: node.first_argument.source)) do |corrector|
            corrector.replace(node, 'raise')
          end
        end

        private

        # Walk ancestors for an enclosing resbody whose variable binding matches
        # the re-raised variable. ResbodyNode children are:
        #   [0] exception types (nil for bare rescue, array for typed)
        #   [1] variable assignment (lvasgn node, or nil)
        #   [2] body
        def enclosed_rescue_binds?(node, var_name)
          node.each_ancestor(:resbody).any? do |resbody|
            assignment = resbody.children[1]
            next false unless assignment&.lvasgn_type?

            assignment.children.first == var_name
          end
        end
      end
    end
  end
end
