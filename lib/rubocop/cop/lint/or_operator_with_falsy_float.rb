# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Disabled — see config/default.yml. Ruby `||` treats only nil and false as
      # falsy; 0.0 and 0 are truthy, so `score || 1.0` already preserves a
      # zero. This cop's premise ("`||` treats 0.0 as falsy") confuses Ruby
      # truthiness with C/Python/JS numeric falsiness and was empirically
      # disproven (`0.0 || 1.0 #=> 0.0`). Kept loadable for historical reference;
      # every offense it would raise is a false positive and the autocorrect is
      # a semantic no-op for numeric values.
      class OrOperatorWithFalsyFloat < Base
        MSG = '`||` treats explicit `0.0` as falsy for numeric field `%<field>s`. Use `%<field>s.nil? ? %<fallback>s : %<field>s`.'

        # Stems that indicate a numeric semantic where 0 is a valid value.
        NUMERIC_NAME_PATTERNS = %w[
          confidence score rate ratio probability
          amount balance count quantity duration
          distance lat lng latitude longitude
        ].freeze

        def_node_matcher :or_node?, <<~PATTERN
          (or $_ $_)
        PATTERN

        def on_or(node)
          lhs, rhs = or_node?(node)
          return unless lhs && rhs
          return unless numeric_literal?(rhs)
          return unless numeric_named?(lhs)

          field_source = lhs.source
          fallback_source = rhs.source

          add_offense(node, message: format(MSG, field: field_source, fallback: fallback_source))
        end

        private

        # Float and integer literals are both suspect — integer 0 is falsy too.
        def numeric_literal?(node)
          node.float_type? || node.int_type?
        end

        # Check if the LHS expression carries a numeric name. Traverses through
        # common AST shapes: method calls (obj.score), ivars (@score), lvars,
        # constants, and safe navigation (obj&.score).
        def numeric_named?(node)
          name = extract_name(node)
          return false unless name

          downcased = name.downcase
          NUMERIC_NAME_PATTERNS.any? { |pattern| downcased.include?(pattern) }
        end

        def extract_name(node)
          case node.type
          when :send
            # obj.confidence, score, self.score, obj&.score
            node.method_name.to_s
          when :lvar, :ivar, :cvar
            node.children.first.to_s
          when :gvar
            node.children.first.to_s.delete_prefix('$')
          when :const
            node.children[1].to_s
          end
        end
      end
    end
  end
end
