# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Flags when a namespace has code split between `app/models/` top level and
      # `app/lib/`. A namespace should exist in one canonical location. When the same
      # CamelCase name appears as both `app/models/foo_catalog.rb` and
      # `app/lib/foo_catalog/`, the module in `app/models/` is misplaced — it should
      # live alongside its companion files in `app/lib/`.
      #
      # @example
      #
      #   # bad — namespace split between app/models/ and app/lib/
      #   # app/models/order_catalog.rb       ← flagged
      #   # app/lib/order_catalog/line_item.rb  ← companion exists here
      #
      #   # good — namespace fully in app/lib/
      #   # app/lib/order_catalog.rb
      #   # app/lib/order_catalog/line_item.rb
      #
      #   # good — namespace fully in app/models/
      #   # app/models/bank.rb  (namespace anchor)
      #   # app/models/bank/account.rb
      #
      class CrossDirectoryNamespaceSplit < Base
        MSG = 'Namespace `%<name>s` is split between app/models/ and app/lib/. Move the app/models/ file to app/lib/ to consolidate the namespace.'

        def on_new_investigation
          file_path = processed_source.file_path

          return unless models_top_level?(file_path)

          snake_name = File.basename(file_path, '.rb')
          return if snake_name == 'application_record'

          # Check if an app/lib/<snake_name>/ directory or app/lib/<snake_name>.rb exists.
          return unless has_lib_counterpart?(file_path, snake_name)

          # Namespace anchors (app/models/<name>/ exists alongside this file) are
          # legitimate — they define the module for the subdirectory.
          return if has_subdirectory?(file_path, snake_name)

          # Only flag non-AR definitions — AR models at top level are fine even if
          # a lib directory happens to exist.
          return if inherits_application_record?(processed_source.ast)

          loc = find_definition_loc(processed_source.ast)
          return unless loc

          module_name = snake_name.split('_').map(&:capitalize).join

          add_offense(loc, message: format(MSG, name: module_name))
        end

        private

        def models_top_level?(file_path)
          return false unless file_path.include?('/app/models/')

          relative = file_path[%r{/app/models/(.+)\z}, 1]
          # exclude? is ActiveSupport-only; RuboCop runs cops in pure Ruby.
          relative && !relative.include?('/')
        end

        def has_subdirectory?(file_path, snake_name)
          parent = File.dirname(file_path)
          Dir.exist?(File.join(parent, snake_name))
        end

        def has_lib_counterpart?(file_path, snake_name)
          app_root = file_path[%r{\A(.*?/app)/models/}, 1]
          return false unless app_root

          lib_dir = File.join(app_root, 'lib', snake_name)
          lib_file = File.join(app_root, 'lib', "#{snake_name}.rb")

          Dir.exist?(lib_dir) || File.exist?(lib_file)
        end

        def inherits_application_record?(ast)
          return false unless ast

          node = unwrap_begin(ast)
          return true if inherits_any_class?(node)

          find_ar_inheritance(node)
        end

        def unwrap_begin(node)
          return node unless node.is_a?(AST::Node) && node.begin_type?
          return node unless node.children.any?

          child = node.children.first
          return child if child.is_a?(AST::Node) && (child.module_type? || child.class_type?)

          node
        end

        def inherits_any_class?(node)
          return false unless node.is_a?(AST::Node) && node.class_type?

          !node.children[1].nil?
        end

        def find_ar_inheritance(node)
          return false unless node.is_a?(AST::Node)

          node.children.each do |c|
            next unless c.is_a?(AST::Node)
            return true if inherits_any_class?(c) || find_ar_inheritance(c)
          end

          false
        end

        def find_definition_loc(ast)
          return nil unless ast.is_a?(AST::Node)

          return ast.loc.name if ast.module_type? || ast.class_type?

          ast.children.each do |child|
            next unless child.is_a?(AST::Node)
            next unless child.module_type? || child.class_type?

            return child.loc.name
          end

          nil
        end
      end
    end
  end
end
