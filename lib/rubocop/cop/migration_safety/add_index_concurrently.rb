# typed: strict
# frozen_string_literal: true

require_relative 'base'

module RuboCop
  module Cop
    module MigrationSafety
      class AddIndexConcurrently < Base
        MSG = 'Use `algorithm: :concurrently` with `add_index` in migrations.'

        def on_send(node)
          return unless node.method_name == :add_index
          return if inside_safety_assured_block?(node)

          pair = hash_pair(last_hash_arg(node), :algorithm)
          return if symbol_value?(pair, :concurrently)

          add_offense(node.loc.selector || node, message: MSG)
        end
      end
    end
  end
end
