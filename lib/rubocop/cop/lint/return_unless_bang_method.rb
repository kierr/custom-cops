# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `return unless <bang_method>` and `if <bang_method>` guard clauses
      # where the bang method returns nil or false on success rather than raising on
      # failure. The `return unless require_role!(...)` pattern caused actions to
      # return nil (204 No Content) on success because require_role! returns nil on
      # success and throws :abort on failure.
      #
      # Bang methods conventionally raise on failure, making their return value
      # truthy-by-definition. Guard clauses rely on this convention: `return unless save!`
      # works because save! raises on failure and returns true on success. Methods that
      # deviate from this convention — returning nil/false on success and using side effects
      # (throw, render, redirect) for failure — silently break guard-clause logic.
      #
      # This cop maintains an explicit allowlist of nil-on-success bang methods rather
      # than trying to infer behavior. The pattern is rare but causes undetected runtime
      # misbehavior (204 responses instead of rendered content).
      #
      # @example
      #
      #   # bad — require_role! returns nil on success, throw :abort on failure
      #   return unless require_role!(%w[admin manager])
      #
      #   # good — bang method called without guard; handles its own failure path
      #   require_role!(%w[admin manager])
      #
      #   # good — standard bang method that raises on failure (truthy return)
      #   return unless record.save!
      #
      #   # good — non-bang predicate method
      #   return unless authorized?(action)
      class ReturnUnlessBangMethod < Base
        MSG = 'Do not guard on `%<method>s` — it returns nil/false on success rather than raising on failure. Call it directly and let it handle its own failure path.'

        # Bang methods known to return nil or false on success (not raise on failure).
        # These use side effects (throw :abort, render, redirect) for their failure path.
        # Adding a method here means "this bang method's return value is not a reliable
        # truthiness signal for guard clauses."
        NIL_ON_SUCCESS_METHODS = %i[require_role! authorize_role!].freeze

        # Nodes that indicate a guard clause when they appear as the sole branch of an if.
        GUARD_NODES = %i[return next break].freeze

        # RATIONALE: using on_if rather than on_send — the guard clause
        # is always an `if` node (Ruby desugars `return unless X` to `(if X nil (return))`).
        # Matching on the if node gives access to the condition and branch structure together.
        #
        def on_if(node)
          return unless guard_clause?(node)

          condition = node.condition
          return unless nil_on_success_bang_call?(condition)

          add_offense(condition.loc.selector, message: format(MSG, method: condition.method_name))
        end

        private

        # A guard clause is an if/unless with one empty branch and one branch containing
        # a single flow-control node (return, next, break). Ruby parses
        # `return unless X` as `(if X nil (return))` and `return if X` as `(if X (return) nil)`.
        def guard_clause?(node)
          true_branch = node.children[1]
          false_branch = node.children[2]

          # One branch must be nil (empty), the other must be a guard node.
          if true_branch.nil?
            guard_node?(false_branch)
          elsif false_branch.nil?
            guard_node?(true_branch)
          else
            false
          end
        end

        def guard_node?(node)
          return false unless node

          GUARD_NODES.include?(node.type)
        end

        def nil_on_success_bang_call?(node)
          return false unless node&.send_type?

          NIL_ON_SUCCESS_METHODS.include?(node.method_name)
        end
      end
    end
  end
end
