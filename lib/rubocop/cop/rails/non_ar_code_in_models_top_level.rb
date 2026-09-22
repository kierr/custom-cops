# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Flags non-ActiveRecord code placed directly at `app/models/*.rb` (top level,
      # not in subdirectories). Files in `app/models/` should be ActiveRecord models
      # (classes inheriting from ApplicationRecord) or namespace anchors for model
      # subdirectories. Pure modules and non-AR classes belong in `app/lib/` or in a
      # namespaced subdirectory under `app/models/`.
      #
      # Namespace anchors (e.g. `app/models/bank.rb` when `app/models/bank/` exists)
      # are allowed. STI subclass anchors (e.g. `app/models/bank.rb` that defines
      # `Bank::Account`) are also allowed.
      #
      # @example
      #
      #   # bad — pure module at app/models top level with no subdirectory
      #   # app/models/order_catalog.rb
      #   module OrderCatalog
      #     CATALOG = T.let({}, T::Hash[String, T.untyped])
      #   end
      #
      #   # good — AR model at top level
      #   # app/models/account.rb
      #   class Account < ApplicationRecord
      #   end
      #
      #   # good — namespace anchor (subdirectory exists)
      #   # app/models/device.rb
      #   module Device
      #   end
      #   # app/models/device/cookie.rb also exists
      #
      #   # good — STI base class at top level
      #   # app/models/risk_report.rb
      #   class RiskReport < ApplicationRecord
      #   end
      #
      class NonArCodeInModelsTopLevel < Base
        MSG = 'Non-ActiveRecord %<kind>s in app/models/ top level. Move to app/lib/ or a namespaced subdirectory, or add a RATIONALE comment.'

        # Files exempt from this check — foundational Rails conventions.
        EXEMPT_BASENAMES = %w[application_record.rb].freeze

        def on_new_investigation
          file_path = processed_source.file_path

          return unless models_top_level?(file_path)
          return if exempt_basename?(file_path)
          return if has_subdirectory?(file_path)
          return if inherits_application_record?(processed_source.ast)
          return if justified?(processed_source.ast)

          kind = top_level_definition_kind(processed_source.ast)
          return unless kind # Empty file or no top-level definition — skip.

          loc = find_definition_loc(processed_source.ast)
          return unless loc

          add_offense(loc, message: format(MSG, kind: kind))
        end

        private

        # True for files directly in app/models/*.rb (not in subdirectories or concerns/).
        def models_top_level?(file_path)
          return false unless file_path.include?('/app/models/')

          relative = file_path[%r{/app/models/(.+)\z}, 1]
          return false unless relative

          # Must be a direct file, not in a subdirectory.
          # exclude? is ActiveSupport-only; RuboCop runs cops in pure Ruby.
          !relative.include?('/')
        end

        def exempt_basename?(file_path)
          basename = File.basename(file_path)
          EXEMPT_BASENAMES.include?(basename)
        end

        # True when an app/models/<name>/ directory exists alongside this file,
        # meaning this file is a namespace anchor.
        def has_subdirectory?(file_path)
          basename = File.basename(file_path, '.rb')
          parent = File.dirname(file_path)
          Dir.exist?(File.join(parent, basename))
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

        # True if node is a class that inherits from any parent class.
        # ApplicationRecord direct subclasses, STI subclasses (e.g. AdminUser < User),
        # and other class hierarchies are all legitimate top-level models directory residents.
        def inherits_any_class?(node)
          return false unless node.is_a?(AST::Node) && node.class_type?

          # children[1] is the parent class expression (nil for Object)
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

        # Returns "module" or "class" for the top-level definition, or nil.
        # When the file defines exactly one top-level module/class, the AST root
        # IS that node. When the file has begin/block wrapping multiple definitions,
        # we check children.
        def top_level_definition_kind(ast)
          return nil unless ast.is_a?(AST::Node)

          return 'module' if ast.module_type?
          return 'class' if ast.class_type?

          ast.children.each do |child|
            next unless child.is_a?(AST::Node)

            return 'module' if child.module_type?
            return 'class' if child.class_type?
          end

          nil
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

        # RATIONALE comment within 3 lines above the top-level definition suppresses.
        def justified?(ast)
          return false unless ast.is_a?(AST::Node)

          defn = if ast.module_type? || ast.class_type?
                   ast
                 else
                   ast.children.find { |c| c.is_a?(AST::Node) && (c.module_type? || c.class_type?) }
                 end
          return false unless defn

          comments = processed_source.comments
          node_line = defn.loc.expression.line

          comments.any? do |comment|
            comment_line = comment.loc.expression.line
            comment_line >= node_line - 3 && comment_line < node_line &&
              comment.text.match?(/RATIONALE:/i)
          end
        end
      end
    end
  end
end
