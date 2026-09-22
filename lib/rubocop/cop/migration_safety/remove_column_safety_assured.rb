# typed: strict
# frozen_string_literal: true

require_relative 'base'

module RuboCop
  module Cop
    module MigrationSafety
      class RemoveColumnSafetyAssured < Base
        MSG = 'Wrap `remove_column` in `safety_assured` in migrations.'

        def on_send(node)
          return unless node.method_name == :remove_column
          return if inside_safety_assured_block?(node)

          add_offense(node.loc.selector || node, message: MSG)
        end
      end
    end
  end
end
