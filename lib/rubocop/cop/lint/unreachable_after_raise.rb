# typed: false # RuboCop cop — T is undefined at load time
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects code after `raise`, `return`, `break`, `next`, `throw`, or
      # `fail` statements within the same execution branch that can never execute.
      # Such code is misleading — readers may assume it runs, but control flow
      # has already exited the branch.
      #
      # Only flags statements that are direct siblings of the terminal statement
      # within a `begin` block, method body, or `if`/`case`/`unless` branch.
      # Statements inside separate branches (else/case-when) are not flagged
      # because they may execute on a different path.
      #
      # @example
      #
      #   # bad — unreachable after raise
      #   def process
      #     raise ArgumentError, 'invalid'
      #     log('this never runs')
      #   end
      #
      #   # bad — unreachable after return
      #   def fetch
      #     return cached_value
      #     expensive_computation
      #   end
      #
      #   # bad — unreachable after break
      #   loop do
      #     break if done?
      #     cleanup
      #   end
      #
      #   # good — both paths reachable
      #   if condition
      #     raise 'error'
      #   else
      #     log('runs when condition is false')
      #   end
      #
      #   # good — raise is last statement
      #   def validate!
      #     raise 'invalid' unless valid?
      #   end
      class UnreachableAfterRaise < Base
        MSG = 'Unreachable code detected after `%<keyword>s`. This statement can never execute.'

        # Terminal keywords that unconditionally exit the current branch.
        TERMINAL_METHODS = %i[raise fail return break next throw].freeze

        def on_begin(node)
          _ = check_sibling_statements(node)
        end

        def on_def(node)
          _ = check_sibling_statements(node)
        end

        def on_defs(node)
          _ = check_sibling_statements(node)
        end

        def on_block(node)
          _ = check_sibling_statements(node)
        end

        def on_if(node)
          _ = check_branches(node)
        end

        def on_case(node)
          _ = check_sibling_statements(node)
        end

        def on_while(node)
          _ = check_sibling_statements(node)
        end

        def on_until(node)
          _ = check_sibling_statements(node)
        end

        def on_for(node)
          _ = check_sibling_statements(node)
        end

        def on_kwbegin(node)
          _ = check_sibling_statements(node)
        end

        private

        # Check consecutive sibling statements for terminal-statement-followed-by-code.
        # def/defs nodes have Symbol children (method names) mixed with Node children;
        # only Node children are inspectable statements.
        #
        # `raise`/`fail` are send nodes, but `return`/`break`/`next`/`throw` are
        # their own AST node types — `child.send_type?` alone misses them.
        def check_sibling_statements(container)
          children = container.children.grep(RuboCop::AST::Node)
          return if children.empty?

          children.each_with_index do |child, idx|
            keyword = terminal_keyword(child)
            next unless keyword

            # Flag each sibling that comes after this terminal statement
            ((idx + 1)...children.size).each do |sib_idx|
              sib = children[sib_idx]
              next unless sib

              add_offense(sib, message: format(MSG, keyword: keyword))
            end
          end
        end

        # Returns the terminal keyword symbol if `node` is a terminal statement,
        # nil otherwise. `raise`/`fail` are sends; the rest are dedicated node types.
        def terminal_keyword(node)
          return node.method_name if node.send_type? && TERMINAL_METHODS.include?(node.method_name)

          node.type if %i[return break next throw].include?(node.type)
        end

        # For if/unless nodes, check within each branch body separately.
        def check_branches(if_node)
          [if_node.if_branch, if_node.else_branch].compact.each do |branch|
            next unless branch.begin_type?

            _ = check_sibling_statements(branch)
          end
        end
      end
    end
  end
end
