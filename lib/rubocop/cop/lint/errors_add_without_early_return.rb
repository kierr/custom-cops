# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `errors.add` in custom validation callbacks (registered via
      # `validate :method_name`) where execution continues past the error.
      # Custom validation methods should return after adding errors to prevent
      # confusing double-error messages or continued execution that assumes
      # valid state.
      #
      # The cop cross-references `validate :method_name` declarations with
      # method bodies. Within a flagged method, it detects `errors.add` calls
      # that are not the last statement in their enclosing control-flow branch
      # (if/unless/elsif/else/case/when), or where sibling code runs after the
      # `errors.add` in the same begin-block.
      #
      # @example
      #
      #   # bad — execution continues after errors.add
      #   validate :check_pairing
      #   def check_pairing
      #     if left? && right.blank?
      #       errors.add(:left, 'requires right')
      #     end
      #     check_something_else
      #   end
      #
      #   # good — returns after errors.add
      #   validate :check_pairing
      #   def check_pairing
      #     if left? && right.blank?
      #       errors.add(:left, 'requires right')
      #       return
      #     end
      #     check_something_else
      #   end
      #
      #   # good — return errors.add (early return using errors.add return value)
      #   validate :check_status
      #   def check_status
      #     return errors.add(:status, 'invalid') if final?
      #     check_transitions
      #   end
      class ErrorsAddWithoutEarlyReturn < Base
        MSG = 'Return after `errors.add` in validation callback — continued execution may add conflicting errors or rely on invalid state.'

        # Collects all symbol arguments from `validate :method_name` declarations.
        def_node_search :validate_declarations, <<~PATTERN
          (send nil? :validate {(sym _) (str _)})
        PATTERN

        # Matches errors.add(...) calls — receiver must be `errors`.
        def_node_matcher :errors_add_call?, <<~PATTERN
          (send (send nil? :errors) :add ...)
        PATTERN

        # Matches `return errors.add(...)` — the good pattern.
        def_node_matcher :return_errors_add?, <<~PATTERN
          (return (send (send nil? :errors) :add ...))
        PATTERN

        def on_def(node)
          return unless validation_callback_method?(node)

          # Walk all errors.add calls within this method body.
          node.each_node(:send).select { |n| errors_add_call?(n) && !return_errors_add?(n.parent) }
                               .each do |errors_add|
            next if terminal_in_branch?(errors_add)

            add_offense(errors_add)
          end
        end

        private

        # Returns true if the method name appears in a `validate :name` declaration
        # within the same file.
        def validation_callback_method?(node)
          method_name = node.method_name.to_s
          validate_declarations(processed_source.ast).any? do |decl|
            arg = decl.arguments.first
            next false unless arg

            case arg.type
            when :sym
              arg.value.to_s == method_name
            when :str
              arg.value == method_name
            else
              false
            end
          end
        end

        # Returns true if the errors.add call is the last meaningful statement in
        # its enclosing branch — i.e., nothing executes after it before the branch
        # exits, or the errors.add is followed only by return/throw/raise.
        def terminal_in_branch?(node)
          parent = node.parent
          return true if parent.nil?

          # If the parent is the method def itself (single-statement body),
          # the errors.add is terminal — the method returns immediately after.
          return true if parent.def_type?

          # If wrapped in a return statement, it's terminal by definition.
          return true if parent.return_type?

          # Inside a begin-block (list of statements): check if errors.add is
          # the last statement, or if all subsequent statements are return/throw/raise.
          return terminal_in_begin?(node, parent) if parent.begin_type?

          # If the errors.add is the direct body of an if/unless/elsif/else/when
          # branch (no begin-block wrapper), it is terminal for that branch.
          return true if (parent.if_type? || parent.when_type?) && single_statement_branch?(node, parent)

          # For other wrappers (e.g., method calls like `return errors.add`),
          # check the outer context recursively.
          terminal_in_branch?(parent)
        end

        # In a begin-block, the errors.add is terminal if it is the last child,
        # or if every subsequent statement is an early-exit (return/throw/raise).
        def terminal_in_begin?(node, begin_node)
          siblings = begin_node.children
          idx = siblings.index(node)
          return true unless idx # node not found

          # If it's the last statement in the begin-block, check the begin-block's
          # own context (it may itself be inside a branch).
          return terminal_in_branch?(begin_node) if idx == siblings.size - 1

          # Check if all statements after the errors.add are early exits.
          subsequent = siblings[(idx + 1)..]
          subsequent.all? { |s| early_exit?(s) }
        end

        # Returns true if the node is a single direct child of its parent,
        # meaning it is the only statement in that branch.
        def single_statement_branch?(node, parent)
          if parent.if_type?
            # Check if node is the then-body, else-body, or elsif-body.
            # For if: children are [condition, then_body, else_body_or_elsif]
            then_body = parent.children[1]
            else_body = parent.children[2]

            if then_body.equal?(node)
              # Single-statement then-branch: errors.add is terminal if
              # no else-branch with different logic follows, or if the
              # if-node itself is terminal. But the key question is whether
              # anything runs after this if-block. Check the if's parent context.
              return terminal_in_branch?(parent)
            end

            return terminal_in_branch?(parent) if else_body.equal?(node)

            false
          elsif parent.when_type?
            # When-body is a single statement — terminal if the case itself is terminal.
            terminal_in_branch?(parent.parent) if parent.parent
          else
            false
          end
        end

        # Returns true if the node represents an early exit: return, throw(:abort), raise, break.
        # `throw` is parsed as a send node (kernel method), not a dedicated AST type.
        def early_exit?(node)
          return true if node.return_type?
          return true if node.break_type?
          return true if node.send_type? && %i[raise throw].include?(node.method_name)

          false
        end
      end
    end
  end
end
