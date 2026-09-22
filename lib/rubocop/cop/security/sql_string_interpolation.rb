# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Security
      # Detects string interpolation in SQL query strings passed to connection
      # execute methods. Use parameterized queries instead.
      #
      # @example
      #
      #   # bad
      #   connection.execute("SELECT * FROM users WHERE id = '#{user.id}'")
      #
      #   # good
      #   binds = [ActiveRecord::Relation::QueryAttribute.new('id', user.id, ActiveRecord::Type::Value.new)]
      #   connection.exec_query('SELECT * FROM users WHERE id = $1', 'SQL', binds)
      class SQLStringInterpolation < Base
        MSG = 'Use parameterized queries instead of string interpolation in SQL.'

        CONNECTION_METHODS = %i[execute exec_query select_all select_one select_values select_value].freeze

        def_node_matcher :sql_with_interpolation?, <<~PATTERN
          (send {(send nil? :connection) (send ... :connection)} CONNECTION_METHODS $(dstr ...) ...)
        PATTERN

        def_node_matcher :connection_execute?, <<~PATTERN
          (send $(send nil? :connection) CONNECTION_METHODS $({dstr str} ...) ...)
        PATTERN

        def on_send(node)
          sql_arg = nil
          if (node.method_name == :execute || CONNECTION_METHODS.include?(node.method_name)) &&
             (first_arg = node.first_argument) && first_arg.dstr_type?
            sql_arg = first_arg
          end
          return unless sql_arg

          # Only flag if the interpolated string contains begin nodes (actual interpolation)
          return unless sql_arg.children.any?(&:begin_type?)

          add_offense(sql_arg)
        end
      end
    end
  end
end
