# typed: strict
# frozen_string_literal: true

require_relative 'base'

module RuboCop
  module Cop
    module MigrationSafety
      class AddForeignKeyValidateFalse < Base
        MSG = 'Use `validate: false` with `add_foreign_key`, then validate separately.'

        def on_send(node)
          return unless node.method_name == :add_foreign_key
          return if inside_safety_assured_block?(node)

          pair = hash_pair(last_hash_arg(node), :validate)
          return if false_value?(pair)

          add_offense(node.loc.selector || node, message: MSG)
        end
      end
    end
  end
end
