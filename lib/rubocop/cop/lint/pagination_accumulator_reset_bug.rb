# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects accumulation patterns where a variable is incremented by
      # `.size` of a collection that grows across loop iterations, causing the
      # delta to include previously-counted elements.
      #
      # The canonical bug: `total += items.size` inside a loop that appends to
      # `items` each iteration. On the second iteration, `items.size` includes
      # elements already counted in the first iteration's `total` increment.
      #
      # The fix is to capture `prev_size = items.size` before appending, then
      # use the delta: `total += items.size - prev_size`.
      #
      # @example
      #
      #   # bad — all_results grows each iteration, inflating the delta
      #   loop do
      #     page = fetch_page
      #     all_results.concat(page)
      #     global_position += all_results.size
      #   end
      #
      #   # good — only count the newly-appended elements
      #   loop do
      #     page = fetch_page
      #     prev_size = all_results.size
      #     all_results.concat(page)
      #     global_position += all_results.size - prev_size
      #   end
      #
      #   # good — use appended slice size directly
      #   loop do
      #     page = fetch_page
      #     all_results.push(*page)
      #     global_position += page.size
      #   end
      class PaginationAccumulatorResetBug < Base
        MSG = 'Accumulator incremented by `.size` of a collection that grows each iteration. ' \
              'Capture the size before appending and use the delta, or use the appended slice\'s size directly.'

        APPEND_METHODS = %i[push << concat].freeze

        def on_op_asgn(node)
          return unless node.operator == :+

          # The value side must be <something>.size
          value = node.children[2]
          return unless value&.send_type? && value.method_name == :size

          # The accumulator (LHS variable) and the .size collection must differ.
          accumulator_name = node.children[0].children[0]
          collection_name = extract_name(value.receiver)
          return unless collection_name
          return if accumulator_name == collection_name
          return unless inside_loop?(node)
          return unless collection_appended_in_scope?(node, collection_name)

          add_offense(node.loc.operator)
        end

        private

        # Extract a symbol name from a receiver node. Handles both local
        # variable references (lvar) and implicit-self method calls (send nil).
        def extract_name(node)
          return nil unless node

          case node.type
          when :lvar
            node.children[0]
          when :send
            node.children[0].nil? ? node.children[1] : nil
          end
        end

        def inside_loop?(node)
          node.each_ancestor(:block, :for, :while, :until, :while_post, :until_post).any? do |ancestor|
            if ancestor.block_type?
              method_name = ancestor.send_node.method_name
              %i[each times loop while until step].include?(method_name) ||
                method_name.to_s.start_with?('each_')
            else
              true
            end
          end
        end

        def collection_appended_in_scope?(accumulator_node, collection_name)
          loop_node = nearest_loop(accumulator_node)
          return false unless loop_node

          body = loop_body(loop_node)
          return false unless body

          # Check for method-based append: collection.concat(x), collection.push(x), etc.
          method_append = body.each_node(:send).any? do |send_node|
            next false unless APPEND_METHODS.include?(send_node.method_name)

            extract_name(send_node.receiver) == collection_name
          end

          return true if method_append

          # Check for += append: collection += other
          body.each_node(:op_asgn).any? do |op_asgn_node|
            next false unless op_asgn_node.operator == :+

            op_asgn_node.children[0].children[0] == collection_name
          end
        end

        def nearest_loop(node)
          node.each_ancestor(:block, :for, :while, :until, :while_post, :until_post).find do |ancestor|
            if ancestor.block_type?
              method_name = ancestor.send_node.method_name
              %i[each times loop while until step].include?(method_name) ||
                method_name.to_s.start_with?('each_')
            else
              true
            end
          end
        end

        def loop_body(loop_node)
          case loop_node.type
          when :block
            loop_node.body
          when :for
            loop_node.children[2]
          else
            loop_node.children[1]
          end
        end
      end
    end
  end
end
