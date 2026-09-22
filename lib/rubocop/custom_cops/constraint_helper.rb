# typed: strict
# frozen_string_literal: true

# Shared migration helper for constraint existence checks.
# Duplicated constraint_exists? definitions across migrations are consolidated here.
# Include this module in any migration that needs to check constraint existence
# before adding or removing check constraints.
#
# Usage:
#   class MigrationName < ActiveRecord::Migration[7.1]
#     include ConstraintHelper
#
#     def up
#       add_check_constraint :table, expression, name: 'chk_name' unless constraint_exists?(:table, 'chk_name')
#     end
#   end
module ConstraintHelper
  extend T::Sig
  # Check if a named constraint exists on a table.
  # Uses Postgres system catalogs for reliable detection across schema versions.
  #
  # @param table_name [Symbol, String] the table to check
  # @param constraint_name [String] the constraint name to look up
  # @return [Boolean] true if the constraint exists
  sig { params(table_name: T.any(Symbol, String), constraint_name: String).returns(T::Boolean) }
  def constraint_exists?(table_name, constraint_name)
    # RATIONALE: $2::regclass expects a bare identifier, not a double-quoted string.
    # quote_table_name produces '"schema"."table"' which regclass interprets literally.
    # Passing the raw table name lets regclass resolve it through the search path correctly.
    # Would need a schema-qualified migration context where search_path differs from the target schema to reconsider.
    result = T.cast(
      T.unsafe(self).exec_query(
        'SELECT 1 FROM pg_constraint WHERE conname = $1 AND conrelid = $2::regclass LIMIT 1',
        'Constraint Exists',
        [constraint_name, table_name.to_s]
      ),
      ActiveRecord::Result
    )
    result.any?
  end
end
