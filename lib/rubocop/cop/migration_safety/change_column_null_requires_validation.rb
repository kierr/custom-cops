# typed: strict
# frozen_string_literal: true

require_relative 'base'

# All 21 errors are 7018 "call on T.untyped" from RuboCop AST API
# (Parser::AST::Node methods — no RBI coverage).
module RuboCop
  module Cop
    module MigrationSafety
      class ChangeColumnNullRequiresValidation < Base
        MSG = 'Avoid `change_column_null(..., false)` unless the migration also shows an ' \
              'explicit validation strategy (for example `validate_check_constraint`).'

        def on_send(node)
          return unless node.method_name == :change_column_null
          return unless node.arguments[2]&.false_type?
          return if validation_call_present?

          add_offense(node.loc.selector || node, message: MSG)
        end

        private

        def validation_call_present?
          ast = processed_source.ast
          return false unless ast

          ast.each_descendant(:send).any? { |n| n.method_name == :validate_check_constraint }
        end
      end
    end
  end
end
