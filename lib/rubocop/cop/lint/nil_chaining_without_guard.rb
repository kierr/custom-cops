# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects chained hash access: `var = some_hash['key']; var['nested']`
      # without a preceding nil guard. When the first `[]` returns nil (missing
      # key), the second `[]` raises TypeError at runtime.
      #
      # Only flags when the assignment is itself a `[]` access — general method
      # calls are excluded since most conventionally return Hashes, not nil.
      #
      # @example
      #
      #   # bad — obj may be nil, chaining [] raises TypeError
      #   obj = event_object
      #   T.cast(obj['actionable'], T.nilable(Object))
      #
      #   # good — nil guard before access
      #   obj = event_object
      #   return if obj.nil?
      #   T.cast(obj['actionable'], T.nilable(Object))
      #
      #   # good — safe navigation or blank check
      #   obj = event_object
      #   return if obj.blank?
      #   obj['key']
      #
      #   # good — assigned from literal, not a method call
      #   obj = {}
      #   obj['key']
      #
      class NilChainingWithoutGuard < Base
        MSG = 'Hash access on `%<var>s` without preceding nil guard. `[]` on nil raises TypeError/NoMethodError at runtime. (heuristic)'

        # Methods that constitute a nil guard when called on the variable
        # or when the variable appears as the condition subject.
        GUARD_METHODS = %i[nil? blank? present?].freeze

        # Sentinel: we haven't searched for guards yet.
        UNGUARDED = :unguarded

        def on_send(node)
          return if in_test_file?
          return unless node.method_name == :[]

          receiver = node.receiver
          return unless receiver&.lvar_type?

          var_name = receiver.children[0].to_s
          return unless assigned_from_method_call?(var_name, node)

          return if guarded?(var_name, node)

          message = format(MSG, var: var_name)
          add_offense(node, message:)
        end

        private

        # Check whether the local variable was assigned from a hash/array access
        # (e.g., `var = some_hash['key']`), which can return nil for missing keys.
        # General method calls are excluded — most return Hashes, not nil.
        def assigned_from_method_call?(var_name, access_node)
          scope = access_node.each_ancestor(:begin, :kwbegin, :def, :defs, :block, :module, :class).first
          return false unless scope

          scope.each_node(:lvasgn).any? do |asgn|
            next false unless asgn.children[0].to_s == var_name

            value = asgn.children[1]
            next false if value.nil?

            # Only flag when the RHS is a [] access on another variable or
            # method call — chained hash access is the genuine nil risk.
            next false unless value.send_type? || value.csend_type?

            value.method_name == :[]
          end
        end

        # Check whether a nil guard (`.nil?`, `.blank?`, `.present?`, safe nav,
        # or explicit `== nil`) appears before the access in the same scope.
        # Result is cached per [var_name, scope_id] pair to avoid repeated walks.
        def guarded?(var_name, access_node)
          scope = access_node.each_ancestor(:begin, :kwbegin, :def, :defs, :block).first
          return false unless scope

          scope.each_node(:if, :return, :next, :break).any? do |guard_node|
            guard_before_access?(var_name, guard_node, access_node)
          end
        end

        def guard_before_access?(var_name, guard_node, access_node)
          # Guard must end before the access begins; a guard that contains the
          # access (e.g. `return if obj['key']`) does not protect it.
          guard_range = guard_node.loc.expression
          access_range = access_node.loc.expression
          return false unless guard_range.end_pos <= access_range.begin_pos

          condition = guard_node.respond_to?(:condition) ? guard_node.condition : nil
          return false unless condition

          check_condition?(var_name, condition)
        end

        def check_condition?(var_name, condition)
          return true if guard_method_on_var?(var_name, condition)
          return true if safe_navigation_on_var?(var_name, condition)
          return true if equality_nil_check?(var_name, condition)
          return true if truthy_check?(var_name, condition)

          compound_guard?(var_name, condition)
        end

        # `var.nil?` / `var.blank?` / `var.present?`
        def guard_method_on_var?(var_name, condition)
          return false unless condition.send_type?
          return false unless GUARD_METHODS.include?(condition.method_name)

          receiver = condition.receiver
          receiver&.lvar_type? && receiver.children[0].to_s == var_name
        end

        # `var&.something` — safe navigation is itself a guard
        def safe_navigation_on_var?(var_name, condition)
          return false unless condition.csend_type?

          receiver = condition.receiver
          receiver&.lvar_type? && receiver.children[0].to_s == var_name
        end

        # `var == nil` / `nil == var`
        def equality_nil_check?(var_name, condition)
          return false unless condition.send_type? && condition.method_name == :==

          left, right = condition.children
          (node_lvar_named?(left, var_name) && nil_literal?(right)) ||
            (node_lvar_named?(right, var_name) && nil_literal?(left))
        end

        # `var` used as a truthy check: `return if var` / `next unless var`
        def truthy_check?(var_name, condition)
          condition.lvar_type? && condition.children[0].to_s == var_name
        end

        # Compound: `var.nil? || ...`
        def compound_guard?(var_name, condition)
          return false unless condition.or_type? || condition.and_type?

          condition.children.any? { |child| return check_condition?(var_name, child) }
        end

        def lvar_named?(node, var_name)
          node&.lvar_type? && node.children[0].to_s == var_name
        end

        # Guard against non-Node children (Symbol, nil) in equality checks.
        def node_lvar_named?(node, var_name)
          return false unless node.is_a?(RuboCop::AST::Node)

          lvar_named?(node, var_name)
        end

        def nil_literal?(node)
          node&.nil_type?
        end

        def in_test_file?
          processed_source.file_path&.match?(/(_test\.rb|spec\.rb|test_.*\.rb)\z/)
        end
      end
    end
  end
end
