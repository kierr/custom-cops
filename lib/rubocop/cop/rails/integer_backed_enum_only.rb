# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      class IntegerBackedEnumOnly < Base
        MSG = 'Use integer-backed enums only. Define enums with explicit integer mappings, not string arrays.'

        def on_send(node)
          return unless node.method_name == :enum

          first_arg = node.arguments.first
          return unless first_arg

          if first_arg.sym_type? && node.arguments.size > 1
            # Positional form: enum :status, { ... } or enum :status, [...]
            _ = check_value(node.arguments[1], node.arguments[1])
          elsif first_arg.hash_type?
            # Keyword form: enum status: { ... } or enum status: [...]
            first_arg.pairs.each do |pair|
              _ = check_value(pair, pair.value)
            end
          end
        end

        private

        def check_value(target, value)
          return unless value&.array_type?

          add_offense(target) if value.children.all?(&:sym_type?)
        end
      end
    end
  end
end
