# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `.css(selector).first` or `.css(selector).last` without a
      # subsequent nil guard on the result. Nokolexbor/Nokogiri `.css()`
      # returns a NodeSet; calling `.first` or `.last` on an empty set returns
      # nil. Using the result without checking for nil raises NoMethodError.
      #
      # The canonical fix (commits 46727691a, 80f782991) extracts to a local
      # variable with a nil guard: `table = doc.css('table').first; return
      # unless table`. Safe navigation (`&.`) on the chained call is also
      # accepted.
      #
      # `at_css` calls are excluded — `at_css` already returns nil directly
      # and developer expectation differs from the `.css().first` pattern.
      #
      # `.first(n)` with a numeric argument is excluded — that form returns an
      # Array, not nil, when the NodeSet has fewer than n elements.
      #
      # @example
      #
      #   # bad — .first on empty NodeSet returns nil, chained call crashes
      #   doc.css('table').first.css('tr')
      #
      #   # bad — assigned but used without a nil guard
      #   table = doc.css('table').first
      #   table.css('tr')
      #
      #   # good — nil guard before use
      #   table = doc.css('table').first
      #   return if table.nil?
      #   table.css('tr')
      #
      #   # good — safe navigation on chained call
      #   doc.css('table').first&.css('tr')
      #
      #   # good — at_css returns nil directly, developer expectation differs
      #   doc.at_css('table')
      #
      class NokolexborCssFirstWithoutNilGuard < Base
        MSG = 'Use a nil guard after `.css(...).%<method>s` — an empty NodeSet makes it return nil, causing NoMethodError on chained calls.'

        # Methods on NodeSet that return a single element (or nil).
        DANGEROUS_METHODS = %i[first last].freeze

        # Methods that constitute a nil guard when called on the variable
        # or when the variable appears as the condition subject.
        GUARD_METHODS = %i[nil? blank? present?].freeze

        # Matches `doc.css(...).first` or `doc.css(...).last` — a send node
        # whose method is :first/:last and whose receiver is a send to :css.
        # `.first(n)` with arguments is excluded.
        def_node_matcher :css_first_or_last?, <<~PATTERN
          (send $(send _ :css ...) {:first :last})
        PATTERN

        # Matches `doc.css(...).first&.something` — safe-navigated chain.
        def_node_matcher :safe_navigated_css_first_or_last?, <<~PATTERN
          (csend $(send _ :css ...) {:first :last})
        PATTERN

        def on_send(node)
          matched = css_first_or_last?(node)
          return unless matched

          # Exclude at_css — it returns nil directly and developer intent differs.
          return if matched.method_name == :at_css

          # Exclude .first(n) with arguments — returns Array, not nil.
          return if node.arguments.any?

          # If the .first/.last result is immediately safe-navigated
          # (e.g., doc.css('x').first&.text), the parent will be a csend.
          return if safe_navigation_parent?(node)

          # If the .first/.last result is assigned to a local variable,
          # check whether that variable is guarded before use.
          return if assigned_with_guard?(node)

          # Remaining case: the .first/.last result is used directly
          # without safe navigation or guard (chained method call, etc.).
          add_offense(node.loc.selector, message: format(MSG, method: node.method_name))
        end

        private

        # The parent of `doc.css('x').first` is a csend when written as
        # `doc.css('x').first&.something` — safe navigation makes it guarded.
        def safe_navigation_parent?(node)
          parent = node.parent
          parent&.csend_type? && parent.receiver == node
        end

        # Check if the node is the RHS of a local variable assignment and
        # that the variable has a nil guard before subsequent use.
        def assigned_with_guard?(node)
          parent = node.parent
          return false unless parent&.lvasgn_type?
          return false unless parent.children[1] == node

          var_name = parent.children[0].to_s
          scope = parent.each_ancestor(:begin, :kwbegin, :def, :defs, :block).first
          return false unless scope

          guarded?(var_name, parent, scope)
        end

        # Walk the scope for guard nodes (if/return/next/break) that appear
        # after the assignment and before any unguarded use of the variable.
        def guarded?(var_name, assignment, scope)
          assign_pos = assignment.loc.expression.end_pos

          scope.each_node(:if, :return, :next, :break).any? do |guard_node|
            guard_range = guard_node.loc.expression
            next false unless guard_range.begin_pos >= assign_pos

            # The guard must precede or contain the first use — not follow it.
            # A guard that appears after the access does not protect it.
            condition = guard_node.respond_to?(:condition) ? guard_node.condition : nil
            next false unless condition

            return check_condition?(var_name, condition)
          end
        end

        def check_condition?(var_name, condition)
          return true if guard_method_on_var?(var_name, condition)
          return true if truthy_check?(var_name, condition)
          return true if equality_nil_check?(var_name, condition)

          compound_guard?(var_name, condition)
        end

        # `var.nil?` / `var.blank?` / `var.present?`
        def guard_method_on_var?(var_name, condition)
          return false unless condition.send_type?
          return false unless GUARD_METHODS.include?(condition.method_name)

          receiver = condition.receiver
          receiver&.lvar_type? && receiver.children[0].to_s == var_name
        end

        # `var` used as a truthy check: `return if var` / `next unless var`
        def truthy_check?(var_name, condition)
          condition.lvar_type? && condition.children[0].to_s == var_name
        end

        # `var == nil` / `nil == var`
        def equality_nil_check?(var_name, condition)
          return false unless condition.send_type? && condition.method_name == :==

          left, right = condition.children
          (lvar_named?(left, var_name) && nil_literal?(right)) ||
            (lvar_named?(right, var_name) && nil_literal?(left))
        end

        # Compound: `var.nil? || ...`
        def compound_guard?(var_name, condition)
          return false unless condition.or_type? || condition.and_type?

          condition.children.any? { |child| return check_condition?(var_name, child) }
        end

        def lvar_named?(node, var_name)
          return false unless node.is_a?(RuboCop::AST::Node)

          node.lvar_type? && node.children[0].to_s == var_name
        end

        def nil_literal?(node)
          node&.nil_type?
        end
      end
    end
  end
end
