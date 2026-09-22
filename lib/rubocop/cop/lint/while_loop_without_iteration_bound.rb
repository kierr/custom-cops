# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects unbounded `loop do` blocks that risk infinite iteration.
      #
      # A `loop do` block with a conditional `break` but no counter variable
      # risks infinite looping when the external condition never converges.
      # Add a counter with a maximum iteration guard, or use a bounded
      # iterator like `each`, `times`, or `upto`.
      #
      # `while` and `until` loops with non-trivial conditions (e.g.
      # `while cursor < array.length`) are considered self-bounded and are
      # not flagged. Only `while true` / `until false` — effectively
      # unbounded — are flagged.
      #
      # @example
      #
      #   # bad — no counter, risk of infinite loop
      #   loop do
      #     response = fetch_page(token)
      #     break if response.last_page?
      #   end
      #
      #   # good — counter with maximum iteration guard
      #   loop do
      #     break if attempts >= MAX_RETRIES
      #     attempts += 1
      #     response = fetch_page(token)
      #     break if response.last_page?
      #   end
      #
      #   # good — bounded while condition
      #   while cursor < items.length
      #     process(items[cursor])
      #     cursor += 1
      #   end
      #
      #   # good — external convergence with counter as backup bound
      #   attempts = 0
      #   loop do
      #     break if attempts >= MAX_RETRIES
      #     attempts += 1
      #     result = try_connect
      #     break if result.success?
      #   end
      #
      class WhileLoopWithoutIterationBound < Base
        MSG = 'Add an iteration counter with a maximum guard to prevent unbounded looping.'

        # Iteration methods that are inherently bounded — never flag these.
        BOUNDED_ITERATORS = %i[each times upto downto step loop].freeze

        # Methods called on the loop body that indicate external convergence
        # without a counter. Only used for `loop do` — bounded iterators
        # are excluded earlier.
        # Not used for filtering — we flag `loop do` with conditional break
        # and no counter, regardless of what methods are called.

        def on_while(node)
          return unless trivially_unbounded_condition?(node.condition)

          add_offense(node)
        end

        def on_until(node)
          return unless trivially_unbounded_until_condition?(node.condition)

          add_offense(node)
        end

        # Only investigate `loop do` blocks — not other method blocks.
        def on_block(node)
          return unless loop_call?(node.send_node)

          body = node.body
          return unless body

          return unless conditional_break?(body)
          return if counter_variable?(body)

          add_offense(node)
        end

        private

        # `while true` — the condition is the literal `true` with no
        # comparison, making the loop unbounded unless `break` exits it.
        def trivially_unbounded_condition?(condition)
          condition.true_type?
        end

        # `until false` — the condition is the literal `false`, so the
        # loop body runs indefinitely.
        def trivially_unbounded_until_condition?(condition)
          condition.false_type?
        end

        def loop_call?(send_node)
          send_node.method_name == :loop
        end

        # Does the body contain `break if <condition>` or `break unless <condition>`?
        # These are conditional breaks — the loop depends on external convergence.
        #
        # In the AST, `break if cond` parses as `(if cond (break) nil)` and
        # `break unless cond` parses as `(if cond nil (break))`. The `break` is
        # a child of the `if` node, not the other way around. So we look for
        # `if` nodes that contain a `break` in one of their branches.
        def conditional_break?(body)
          body.each_node(:if).any? do |if_node|
            # Only consider `if` nodes where break is the sole statement in one
            # branch — this is `break if cond` / `break unless cond`, not an
            # `if` block that happens to contain a `break` among other logic.
            true_branch = if_node.children[1]
            false_branch = if_node.children[2]

            bare_break?(true_branch) || bare_break?(false_branch)
          end
        end

        # Is this node a standalone `break` with no arguments?
        # Matches `(break)` — the form used in `break if cond`.
        def bare_break?(node)
          node&.break_type? && node.children.empty?
        end

        # Heuristic: a counter variable is a local variable (lvasgn) whose
        # value is an arithmetic operation involving itself (e.g., `i += 1`,
        # `attempts = attempts + 1`). This distinguishes iteration counters
        # from simple reassignments.
        #
        # Also accepts `i += 1` shorthand (or-asgn with op-asgn).
        def counter_variable?(body)
          assignments = body.each_node(:lvasgn).to_a
          op_assignments = body.each_node(:op_asgn).to_a

          # `attempts += 1` is an op-asgn where the target is an lvasgn
          # (not lvar — RuboCop wraps the target as an lvasgn node) and
          # the operator is `+`.
          return true if op_assignments.any? do |node|
            node.node_parts[1] == :+ &&
            node.node_parts[0].lvasgn_type?
          end

          # `counter = counter + 1` — lvasgn where the RHS is an arithmetic
          # expression referencing the same variable.
          assignments.any? do |node|
            rhs = node.children[1]
            next false unless rhs

            references_self?(rhs, node.children[0])
          end
        end

        # Does the RHS expression reference the named variable?
        # Catches `counter + 1`, `counter.succ`, `counter.next`.
        # Guard: send node children include nil receivers and non-AST values
        # (method name symbols) — skip those safely.
        def references_self?(node, var_name)
          return false unless node.is_a?(RuboCop::AST::Node)

          case node.type
          when :lvar
            node.children[0] == var_name
          when :send
            # `counter + 1` is (send (lvar counter) :+ (int 1)).
            # Children are [receiver, method_name, *args] — receiver and args
            # are AST nodes, method_name is a Symbol.
            node.children.grep(RuboCop::AST::Node).any? do |child|
              references_self?(child, var_name)
            end
          when :begin
            node.children.any? { |child| references_self?(child, var_name) }
          else
            false
          end
        end
      end
    end
  end
end
