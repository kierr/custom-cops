# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `.css(selector).first`, `.css(selector).last`, or
      # `.css(selector)[n]` without a nil guard on Nokogiri and Nokolexbor
      # documents. Both libraries' `.css()` returns a NodeSet; calling
      # `.first`, `.last`, or `[n]` on an empty set returns nil. Using the
      # result without a nil check raises NoMethodError on chained calls.
      #
      # The canonical fix extracts to a local variable with a nil guard:
      #   table = doc.css('table').first
      #   return unless table
      #   table.css('tr')
      # Safe navigation (`&.`) on the chained call is also accepted.
      #
      # `at_css` calls are excluded -- `at_css` returns nil directly and
      # developer expectation differs from the `.css().first` pattern.
      #
      # `.first(n)` with a numeric argument is excluded -- that form returns
      # an Array, not nil, when the NodeSet has fewer than n elements.
      #
      # @example
      #
      #   # bad -- .first on empty NodeSet returns nil, chained call crashes
      #   doc.css('table').first.css('tr')
      #
      #   # bad -- bracket access on empty NodeSet returns nil
      #   doc.css('table')[0].css('tr')
      #
      #   # bad -- assigned but used without a nil guard
      #   table = doc.css('table').first
      #   table.css('tr')
      #
      #   # good -- nil guard before use
      #   table = doc.css('table').first
      #   return if table.nil?
      #   table.css('tr')
      #
      #   # good -- safe navigation on chained call
      #   doc.css('table').first&.css('tr')
      #
      #   # good -- at_css returns nil directly, developer expectation differs
      #   doc.at_css('table')
      #
      class CssFirstWithoutNilGuard < Base
        MSG = 'Use a nil guard after `.css(...).%<method>s` -- an empty NodeSet makes it return nil, causing NoMethodError on chained calls.'

        # Methods on NodeSet that return a single element (or nil).
        DANGEROUS_METHODS = %i[first last].freeze

        # Methods that constitute a nil guard when called on the variable
        # or when the variable appears as the condition subject.
        GUARD_METHODS = %i[nil? blank? present?].freeze

        # Matches `doc.css(...).first` or `doc.css(...).last` -- a send node
        # whose method is :first/:last and whose receiver is a send to :css.
        # `.first(n)` with arguments is excluded.
        def_node_matcher :css_first_or_last?, <<~PATTERN
          (send $(send _ :css ...) {:first :last})
        PATTERN

        # Matches `doc.css(...)[n]` -- bracket access on a css() result.
        def_node_matcher :css_bracket_access?, <<~PATTERN
          (send $(send _ :css ...) :[] ...)
        PATTERN

        # Matches safe-navigated first/last chains.
        def_node_matcher :safe_navigated_css_first_or_last?, <<~PATTERN
          (csend $(send _ :css ...) {:first :last})
        PATTERN

        def on_send(node)
          if (css_call = css_first_or_last?(node))
            process_first_or_last(node, css_call)
          elsif (css_call = css_bracket_access?(node))
            process_bracket_access(node, css_call)
          end
        end

        private

        def process_first_or_last(node, css_call)
          # Exclude at_css -- it returns nil directly and developer intent differs.
          return if css_call.method_name == :at_css

          # Exclude .first(n) with arguments -- returns Array, not nil.
          return if node.arguments.any?

          # Safe navigation on the chained call is a guard.
          return if safe_navigation_parent?(node)

          # Assignment with a subsequent nil guard is accepted.
          return if assigned_with_guard?(node)

          add_offense(node.loc.selector, message: format(MSG, method: node.method_name))
        end

        def process_bracket_access(node, css_call)
          # Exclude at_css.
          return if css_call.method_name == :at_css

          # Safe navigation on the chained call is a guard.
          return if safe_navigation_parent?(node)

          # Assignment with a subsequent nil guard is accepted.
          return if assigned_with_guard?(node)

          add_offense(node.loc.selector, message: format(MSG, method: '[]'))
        end

        # The parent of `doc.css('x').first` is a csend when written as
        # `doc.css('x').first&.something` -- safe navigation makes it guarded.
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

            condition = guard_node.respond_to?(:condition) ? guard_node.condition : nil
            next false unless condition

            guard_met?(var_name, condition)
          end
        end

        def guard_met?(var_name, condition)
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

          condition.children.any? { |child| guard_met?(var_name, child) }
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
