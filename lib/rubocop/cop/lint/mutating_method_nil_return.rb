# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects in-place mutating methods (`.uniq!`, `.compact!`, `.flatten!`,
      # `.reject!`, `.select!`, `.slice!`, `.sort!`) where the return value is
      # captured or chained. These methods return `nil` when no changes are made,
      # which causes NoMethodError on subsequent chained calls or silently assigns
      # nil to the capturing variable.
      #
      # The `.uniq!` variant was fixed in a production bug
      # (`blacklist.uniq!` returned nil).
      #
      # @example
      #
      #   # bad — nil assigned when no duplicates removed
      #   result = arr.uniq!
      #
      #   # bad — nil returned when no nil elements, crashes next .uniq!
      #   arr.compact!.uniq!
      #
      #   # good — non-bang always returns the new array
      #   result = arr.uniq
      #
      #   # good — in-place mutation without capturing the return
      #   result = build_list
      #   result.compact!
      #
      #   # good — safe navigation acknowledges nil possibility
      #   arr&.compact!
      class MutatingMethodNilReturn < Base
        MSG = '`%<method>s` returns nil when no changes are made. Use the non-bang variant `%<safe>s` when capturing the result, or call in-place without capturing.'

        MUTATING_METHODS = %i[uniq! compact! flatten! reject! select! slice! sort!].freeze

        def on_send(node)
          return unless MUTATING_METHODS.include?(node.method_name)
          return if safe_navigation?(node)
          return if standalone_statement?(node)
          return unless return_value_used?(node)

          method_name = node.method_name
          safe_method = method_name.to_s.delete_suffix('!')

          add_offense(node.loc.selector, message: format(MSG, method: method_name, safe: safe_method))
        end

        private

        # The return value is "used" when the node is anything other than a
        # standalone statement — assigned, chained, passed as argument, etc.
        def return_value_used?(node)
          parent = node.parent
          return false unless parent

          # Direct assignment: result = arr.uniq!
          return true if parent.lvasgn_type?

          # Instance/class/global variable assignment
          return true if parent.ivasgn_type? || parent.cvasgn_type? || parent.gvasgn_type?

          # Chained: node is receiver of another send — arr.compact!.uniq!
          return true if parent.send_type? && parent.children.first == node

          # Passed as argument: something(arr.uniq!)
          return true if parent.send_type? && parent.arguments.include?(node)

          # Used in array/hash, return, pair, condition
          return true if parent.array_type? || parent.hash_type? || parent.pair_type?
          return true if parent.return_type?
          return true if parent.if_type? && parent.condition == node

          # Compound conditions: arr.uniq! && something
          return true if parent.and_type? || parent.or_type?

          false
        end

        # A standalone statement: the mutating call is a direct child of a
        # begin/block/def body, meaning its return value is discarded.
        # This is the safe pattern — the mutation happens in place and the
        # nil return is ignored.
        def standalone_statement?(node)
          parent = node.parent
          return true unless parent

          parent.begin_type? || parent.kwbegin_type? ||
            parent.def_type? || parent.defs_type?
        end

        def safe_navigation?(node)
          node.csend_type?
        end
      end
    end
  end
end
