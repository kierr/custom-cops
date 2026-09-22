# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects side-effect arithmetic inside `filter_map` blocks, specifically
      # the pattern `expr || (counter += nil)` which raises TypeError because
      # `+= nil` on an Integer is invalid. Use explicit if/else instead.
      #
      # @example
      #
      #   # bad — += nil raises TypeError
      #   filter_map do |item|
      #     build_row(item) || (skipped += nil)
      #   end
      #
      #   # good
      #   filter_map do |item|
      #     row = build_row(item)
      #     if row
      #       row
      #     else
      #       skipped += 1
      #       nil
      #     end
      #   end
      class FilterMapSideEffect < Base
        MSG = 'Side-effect arithmetic in `filter_map` block is error-prone. Use explicit if/else instead.'

        def_node_matcher :filter_map_block?, <<~PATTERN
          (block (send _ :filter_map) ...)
        PATTERN

        def_node_matcher :or_with_arithmetic?, <<~PATTERN
          (or _ (begin (lvasgn _ (begin (send (lvar _) :+ nil)))))
        PATTERN

        def_node_matcher :or_with_op_assign?, <<~PATTERN
          (or _ (or_asgn (lvasgn _ (begin (send (lvar _) :+ {nil (nil)}))) ...))
        PATTERN

        def on_block(node)
          return unless filter_map_block?(node)

          nil unless contains_arithmetic_in_or?(node.body)
        end

        private

        def contains_arithmetic_in_or?(node)
          return false unless node

          case node.type
          when :or
            right = unwrap_begin(node.children[1])
            # Match `counter += nil` which is `(op_asgn (lvasgn :counter) :+ (nil))`
            if op_assign_with_nil?(right)
              add_offense(node)
              return true
            end
            contains_arithmetic_in_or?(node.children[0]) || contains_arithmetic_in_or?(node.children[1])
          when :begin
            node.children.any? { |child| contains_arithmetic_in_or?(child) }
          else
            false
          end
        end

        def op_assign_with_nil?(node)
          # `skipped += nil` parses as (op_asgn (lvasgn :skipped) :+ (nil)),
          # not (lvasgn :skipped (send (lvar :skipped) :+ nil)) as the old
          # matcher assumed. Handle the op_asgn shape directly.
          return op_asgn_increment_with_nil?(node) if node.type == :op_asgn
          return false unless node.type == :lvasgn

          value = node.children[1]
          return false unless value&.send_type?
          return false unless value.method_name == :+

          rhs = value.children[2]
          rhs.nil? || rhs&.nil_type?
        end

        def op_asgn_increment_with_nil?(node)
          return false unless node.children[1] == :+

          rhs = node.children[2]
          rhs&.nil_type?
        end

        # Parenthesized RHS in `x || (skipped += nil)` parses with a begin wrapper.
        def unwrap_begin(node)
          return node unless node&.begin_type?
          return node unless node.children.size == 1

          node.children.first
        end
      end
    end
  end
end
