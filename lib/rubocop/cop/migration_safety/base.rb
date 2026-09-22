# typed: strict
# frozen_string_literal: true

# from RuboCop::AST::ProcessedSource API (incomplete RBIs). See AGENTS.md rule #1.

module RuboCop
  module Cop
    module MigrationSafety
      class Base < ::RuboCop::Cop::Base
        private

        def last_hash_arg(node)
          arg = node.arguments.last
          arg if arg&.hash_type?
        end

        def hash_pair(hash_node, key_name)
          return unless hash_node

          hash_node.pairs.find do |pair|
            pair.key.sym_type? && pair.key.value == key_name
          end
        end

        def symbol_value?(pair, expected)
          value = pair&.value
          value&.sym_type? && value.value == expected
        end

        def false_value?(pair)
          pair&.value&.false_type?
        end

        def inside_safety_assured_block?(node)
          node.each_ancestor(:block).any? do |ancestor|
            ancestor.send_node&.method_name == :safety_assured
          end
        end
      end
    end
  end
end
