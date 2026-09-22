# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects state transition hash access (e.g., `TRANSITIONS[status]`) where
      # the result is used via safe navigation (`&.include?`, `&.exclude?`) without
      # an explicit nil guard that reports an error for unknown states.
      #
      # When the hash key is absent (unknown state), `hash[key]` returns nil.
      # Safe navigation then silently returns nil instead of raising or adding a
      # validation error, allowing invalid transitions to pass undetected.
      #
      # The shared concern `StateTransitionValidatable` handles this correctly by
      # checking `if allowed.nil?` and calling `errors.add`. This cop flags only
      # manual implementations that omit the nil guard.
      #
      # @example
      #
      #   # bad — unknown state silently passes (nil &.include? returns nil, which is falsy,
      #   # but the error path may not distinguish "invalid transition" from "unknown state")
      #   unless VALID_TRANSITIONS[status]&.include?(next_status)
      #     raise "Invalid transition"
      #   end
      #
      #   # bad — same pattern with assignment and safe navigation
      #   allowed = ALLOWED_TRANSITIONS[from_state]
      #   return if allowed&.include?(to_state)
      #
      #   # good — explicit nil guard adds error for unknown state
      #   allowed = TRANSITIONS[previous_status]
      #   unless allowed
      #     errors.add(:status, "Unknown previous status: '#{previous_status}'")
      #     return
      #   end
      #   errors.add(:status, "Invalid transition") if allowed.exclude?(status)
      #
      #   # good — uses fetch with a default empty array (unknown state = no valid transitions)
      #   allowed = TRANSITIONS.fetch(previous_status, [])
      #   return if allowed.include?(status)
      #
      #   # good — uses StateTransitionValidatable concern (not flagged)
      class StateTransitionMissingUnknownStateGuard < Base
        MSG = 'State transition hash access with safe navigation lacks a nil guard for unknown states. Use `fetch` with a default or check `nil?` and add an error before safe-navigating.'

        # Methods invoked via safe navigation on the transition lookup result.
        SAFE_NAV_METHODS = %i[include? exclude?].freeze

        # NodePattern: matches CONSTANT[key] (hash/aref access on a transition constant).
        def_node_matcher :transition_hash_access?, <<~PATTERN
          (send (const nil? {:TRANSITIONS :VALID_TRANSITIONS :ALLOWED_TRANSITIONS :VALID_LIFECYCLE_TRANSITIONS}) :[] ...)
        PATTERN

        def on_csend(node)
          return unless SAFE_NAV_METHODS.include?(node.method_name)

          receiver = node.receiver

          # Case 1: inline CONSTANT[key]&.include?(...) or &.exclude?(...)
          if receiver&.send_type? && transition_hash_access?(receiver)
            return if inside_state_transition_validatable?(node)

            add_offense(node)
            return
          end

          # Case 2: variable safe-nav: allowed&.include?(...) after assignment from CONSTANT[key]
          return unless receiver&.lvar_type?

          var_name = receiver.name
          lvasgn = find_preceding_lvasgn_from_transition_const(node, var_name)
          return unless lvasgn

          return if inside_state_transition_validatable?(node)
          return if nil_guard_exists?(var_name, lvasgn, node)

          add_offense(node)
        end

        private

        # Walk ancestors to find a local variable assignment of the given name
        # whose value is a transition constant hash access.
        def find_preceding_lvasgn_from_transition_const(node, var_name)
          # The csend is typically inside an `if` condition (e.g., `return if allowed&.include?`).
          # Walk up to the begin block that contains the preceding lvasgn.
          container = node.each_ancestor(:begin).first
          return nil unless container

          siblings = container.children
          enclosing = find_enclosing_statement(node, siblings)
          return nil unless enclosing

          idx = siblings.index(enclosing)
          return nil unless idx&.positive?

          # Search backwards for an lvasgn of the variable that reads from a transition constant.
          siblings[0...idx].reverse_each do |sibling|
            next unless sibling&.lvasgn_type? && sibling.name == var_name

            rhs = sibling.expression
            return sibling if rhs && transition_hash_access?(rhs)
          end

          nil
        end

        # Find which top-level child of the begin block contains the given node.
        def find_enclosing_statement(node, siblings)
          siblings.each do |sibling|
            return sibling if sibling == node || ancestor_contains?(sibling, node)
          end
          nil
        end

        # Check if `ancestor` contains `descendant` in its subtree.
        def ancestor_contains?(ancestor, descendant)
          ancestor.each_descendant.any?(descendant)
        end

        # Check if there is a nil guard on the variable between the lvasgn and the
        # csend node. A nil guard is an `if`/`unless` that checks the variable and
        # contains error reporting (errors.add or raise).
        def nil_guard_exists?(var_name, lvasgn_node, csend_node)
          container = lvasgn_node.parent
          return false unless container&.begin_type?

          siblings = container.children
          lvasgn_idx = siblings.index(lvasgn_node)
          csend_enclosing = find_enclosing_statement(csend_node, siblings)
          csend_enclosing_idx = siblings.index(csend_enclosing)
          return false unless lvasgn_idx && csend_enclosing_idx

          # Check statements between assignment and the csend for a nil guard.
          siblings[(lvasgn_idx + 1)...csend_enclosing_idx].any? do |sibling|
            nil_guard_with_error?(sibling, var_name)
          end
        end

        # The concern StateTransitionValidatable already has proper nil handling.
        # Skip nodes that are inside the concern module itself.
        def inside_state_transition_validatable?(node)
          node.each_ancestor(:module).any? do |mod|
            mod.identifier&.source == 'StateTransitionValidatable'
          end
        end

        # Checks if the node is an `if`/`unless` that guards the variable for nil
        # and contains error reporting (errors.add or raise).
        def nil_guard_with_error?(node, var_name)
          return false unless node&.if_type?

          condition = node.condition
          return false unless references_var?(condition, var_name)

          branches = [node.if_branch, node.else_branch].compact
          branches.any? { |branch| contains_error_addition?(branch) }
        end

        def references_var?(node, var_name)
          return false unless node

          case node.type
          when :lvar
            node.name == var_name
          when :send
            node.method_name == :nil? && references_var?(node.receiver, var_name)
          else
            node.children.any? { |child| child.is_a?(Parser::AST::Node) && references_var?(child, var_name) }
          end
        end

        def contains_error_addition?(node)
          return false unless node

          case node.type
          when :send
            node.method_name == :add ||
              (node.method_name == :raise && node.arguments.any?)
          when :begin
            node.children.any? { |child| contains_error_addition?(child) }
          else
            false
          end
        end
      end
    end
  end
end
