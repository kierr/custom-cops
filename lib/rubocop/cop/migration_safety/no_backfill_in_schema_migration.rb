# typed: strict
# frozen_string_literal: true

require_relative 'base'

# All 17 errors are 7018 "call on T.untyped" from RuboCop AST API
# (Parser::AST::Node methods — no RBI coverage).
module RuboCop
  module Cop
    module MigrationSafety
      class NoBackfillInSchemaMigration < Base
        MSG = 'Do not combine schema changes like `add_column` with data backfill like ' \
              '`update_all` in the same migration. Split schema and batch backfill steps.'

        SCHEMA_CHANGE_METHODS = %i[
          add_column add_reference add_index add_foreign_key
          add_check_constraint change_column change_column_null
          change_column_default rename_column remove_column
          remove_index remove_foreign_key create_table
          change_table drop_table
        ].freeze

        def on_send(node)
          return unless node.method_name == :update_all
          return unless schema_change_present?

          add_offense(node.loc.selector || node, message: MSG)
        end

        private

        def schema_change_present?
          ast = processed_source.ast
          return false unless ast

          ast.each_descendant(:send).any? do |send_node|
            SCHEMA_CHANGE_METHODS.include?(send_node.method_name)
          end
        end
      end
    end
  end
end
