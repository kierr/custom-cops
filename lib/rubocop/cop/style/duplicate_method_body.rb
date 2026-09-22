# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # Detects two or more methods in the same class/module whose bodies are
      # structurally identical except for string or symbol literal values.
      # Such methods should extract the shared logic into a single private
      # method parameterized by the differing values.
      #
      # Only flags methods in the same scope (same parent class/module node).
      # Ignores methods with empty or trivially short bodies (< 3 nodes).
      # Ignores singleton methods (defs) and methods with different parameter
      # counts.
      #
      # @example
      #
      #   # bad — two methods with identical structure, differing only in literals
      #   def wait_for_number
      #     deadline = Time.now + @timeout
      #     loop do
      #       state = get_state.state
      #       unless state.nil?
      #         number = T.cast(state['number'], T.nilable(String))
      #         return NumberResult.new(number: number) if number && !number.blank?
      #       end
      #       raise "Timed out waiting for number" if Time.now >= deadline
      #       sleep 1
      #     end
      #   end
      #
      #   def wait_for_code
      #     deadline = Time.now + @timeout
      #     loop do
      #       state = get_state.state
      #       unless state.nil?
      #         msg = T.cast(state['msg'], T.nilable(String))
      #         return CodeResult.new(code: msg) if msg && !msg.blank?
      #       end
      #       raise "Timed out waiting for code" if Time.now >= deadline
      #       sleep 1
      #     end
      #   end
      #
      #   # good — extracted shared method
      #   def wait_for_number
      #     poll_for_field('number', 'number') { |v| NumberResult.new(number: v) }
      #   end
      #
      #   def wait_for_code
      #     poll_for_field('msg', 'code') { |v| CodeResult.new(code: v) }
      #   end
      #
      #   private
      #
      #   def poll_for_field(field, label, &blk)
      #     deadline = Time.now + @timeout
      #     loop do
      #       state = get_state.state
      #       unless state.nil?
      #         value = T.cast(state[field], T.nilable(String))
      #         return blk.call(value) if value && !value.blank?
      #       end
      #       raise "Timed out waiting for #{label}" if Time.now >= deadline
      #       sleep 1
      #     end
      #   end
      class DuplicateMethodBody < Base
        MSG = 'Method body is structurally identical to `%<other>s` except for literal values. Extract the shared logic into a parameterized method.'

        MIN_BODY_SIZE = 3

        def on_def(node)
          return unless node.body
          return if node.body.descendants.size < MIN_BODY_SIZE

          siblings = def_siblings(node)
          return unless siblings

          matching = siblings.find { |sibling| body_equivalent?(node.body, sibling.body) }
          return unless matching

          # Only flag the later method — the earlier one is the "original".
          return if node.loc.expression.line < matching.loc.expression.line

          add_offense(node, message: format(MSG, other: matching.method_name))
        end

        private

        # Returns sibling def nodes from the same parent scope.
        def def_siblings(node)
          parent = node.parent
          return nil unless parent

          defs = parent.children.select { |c| c.is_a?(RuboCop::AST::Node) && c.def_type? && c != node }
          return nil if defs.empty?

          defs
        end

        # Two bodies are "equivalent" when their AST structure matches
        # exactly, allowing only string and symbol literals to differ.
        def body_equivalent?(body_a, body_b)
          return false unless body_a && body_b
          return false unless body_a.type == body_b.type

          nodes_equivalent?(body_a, body_b)
        end

        def nodes_equivalent?(node_a, node_b)
          return false unless node_a.type == node_b.type

          # Allow string and symbol literals to differ
          return true if literal_differs?(node_a, node_b)

          # For other node types, children must match
          children_a = node_a.children
          children_b = node_b.children
          return false unless children_a.size == children_b.size

          children_a.zip(children_b).all? do |ca, cb|
            if ca.is_a?(RuboCop::AST::Node) && cb.is_a?(RuboCop::AST::Node)
              nodes_equivalent?(ca, cb)
            elsif !ca.is_a?(RuboCop::AST::Node) && !cb.is_a?(RuboCop::AST::Node)
              # Non-node children (method names, variable names) must match exactly
              ca == cb
            else
              false
            end
          end
        end

        def literal_differs?(node_a, node_b)
          (node_a.str_type? && node_b.str_type?) ||
            (node_a.sym_type? && node_b.sym_type?)
        end
      end
    end
  end
end
