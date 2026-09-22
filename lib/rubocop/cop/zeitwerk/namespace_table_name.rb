# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Zeitwerk
      # Flags namespaced models that don't declare `self.table_name` when
      # Zeitwerk would infer the wrong table. For a module like `Catalog`,
      # Zeitwerk infers `Catalog::Entry` → `catalog/entry` as the table name,
      # but the actual table is `catalog_entries`. Without an explicit
      # declaration, Rails silently uses the wrong table.
      #
      # Configure the namespace(s) to check via `Namespaces` in .rubocop.yml.
      #
      # @example
      #   # bad
      #   module Catalog
      #     class Entry < ApplicationRecord
      #     end
      #   end
      #
      #   # good
      #   module Catalog
      #     class Entry < ApplicationRecord
      #       self.table_name = 'catalog_entries'
      #     end
      #   end
      class NamespaceTableName < Base
        MSG = 'Namespaced model must declare `self.table_name`. Zeitwerk infers the wrong table for namespaced models.'

        # Default namespace to check. Override via `Namespaces` in .rubocop.yml.
        # Accepts a single string or array of strings.
        NAMESPACE_DEFAULT = 'Source'.freeze

        def_node_matcher :namespaced_class?, <<~PATTERN
          (class (const (const nil? _) _) ...)
        PATTERN

        def on_class(node)
          return unless namespaced_class?(node)

          parent_const = node.children.first.children.first
          parent_name = parent_const.children.last.to_s
          return unless watched_namespaces.include?(parent_name)

          body = node.body
          return unless body

          has_table_name = find_table_name_declaration(body)
          return if has_table_name

          add_offense(node.loc.name, message: MSG)
        end

        private

        def watched_namespaces
          namespaces = cop_config['Namespaces']
          case namespaces
          when Array
            namespaces.map(&:to_s)
          when String
            [namespaces]
          else
            [NAMESPACE_DEFAULT]
          end
        end

        def find_table_name_declaration(body)
          return false unless body

          body.each_node(:send).any? do |send_node|
            send_node.method_name == :table_name= &&
              send_node.receiver&.self_type?
          end
        end
      end
    end
  end
end
