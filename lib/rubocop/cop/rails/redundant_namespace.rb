# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Detects module definitions that wrap exactly one class with no other
      # meaningful definitions. The namespace adds a nesting level without
      # conceptual value — the class can be defined directly at the parent scope.
      #
      # Flags when all three conditions hold:
      #   1. The module body, after excluding scaffolding, is a single class.
      #   2. The file is the only Ruby file in its directory (no sibling types).
      #   3. No other app directory (models, services, etc.) uses the same namespace.
      #
      # Scaffolding excluded from analysis: `extend T::Sig`, `extend T::Helpers`,
      # `extend T::Generic`.
      #
      # @example
      #
      #   # bad — sole file in app/lib/infra/, wraps one class
      #   module Infra
      #     class RedisClient
      #       # ...
      #     end
      #   end
      #
      #   # good — multiple classes justify the namespace
      #   module Http
      #     class Config; end
      #     class Client; end
      #   end
      #
      #   # good — shared constants justify the namespace
      #   module Types
      #     MAX = 100
      #     class Validator; end
      #   end
      #
      #   # good — sibling files exist in the directory
      #   # app/lib/search/indexer.rb + app/lib/search/ranker.rb
      #   module Search
      #     class Indexer; end
      #   end
      #
      class RedundantNamespace < Base
        MSG = 'Module `%<name>s` wraps a single class with no shared definitions. ' \
              'Define the class directly or add sibling types/constants to justify the namespace.'

        SCAFFOLDING_MODULES = %i[Sig Helpers Generic].freeze

        def scaffolding_extend?(node)
          return false unless node.send_type? && node.method_name == :extend

          # extend T::Sig → (send nil :extend (const (const nil :T) :Sig))
          arg = node.children[2]
          return false unless arg&.const_type?

          parent = arg.children.first
          return false unless parent&.const_type? && parent.children.last == :T

          SCAFFOLDING_MODULES.include?(arg.children.last)
        end

        def on_new_investigation
          file_path = processed_source.file_path
          return unless file_path.include?('/app/lib/')

          ast = processed_source.ast
          return unless ast&.module_type?

          dir = File.dirname(file_path)
          return if ruby_files_in(dir).size > 1

          module_name = extract_name(ast.children.first)
          return if namespace_exists_elsewhere?(module_name, file_path)

          body = ast.children.last
          return unless body
          return unless single_class_wrapper?(body)

          return if bare_class_name_collides?(body)

          add_offense(ast.loc.name, message: format(MSG, name: module_name))
        end

        private

        # Skip if the bare class name already exists as a loaded constant
        # (gem, stdlib, etc.) — the namespace exists to disambiguate.
        def bare_class_name_collides?(body)
          meaningful = flatten_body(body).reject { |node| scaffolding_extend?(node) }
          return false unless meaningful.size == 1 && meaningful.first.class_type?

          class_node = meaningful.first.children.first
          class_name = extract_name(class_node)
          return false unless class_name

          Object.const_defined?(class_name)
        end

        # Directories (relative to app/) where a namespace might have real breadth beyond lib.
        APP_DIR_SUFFIXES = %w[models services controllers consumers jobs].freeze

        def namespace_exists_elsewhere?(_module_name, file_path)
          # Extract the snake_case directory name directly from the file path.
          # app/lib/billing/invoice_builder.rb → "billing"
          underscored = file_path[%r{/app/lib/([^/]+)/}, 1]
          return false unless underscored

          app_root = file_path[%r{\A(.*?/app)/lib/}, 1]
          return false unless app_root

          APP_DIR_SUFFIXES.any? do |suffix|
            Dir.glob(File.join(app_root, suffix, underscored, '**', '*.rb')).any?
          end
        end

        def ruby_files_in(dir)
          Dir.glob(File.join(dir, '*.rb'))
        end

        # True when the module body is exactly one class definition after
        # stripping scaffolding extends.
        def single_class_wrapper?(body)
          children = flatten_body(body)
          meaningful = children.reject { |node| scaffolding_extend?(node) }
          meaningful.size == 1 && meaningful.first.class_type?
        end

        # Unwrap begin nodes so we can iterate the module body uniformly.
        def flatten_body(body)
          if body.begin_type?
            body.children
          else
            [body]
          end
        end

        def extract_name(node)
          return node.to_s unless node&.const_type?

          node.children.last.to_s
        end
      end
    end
  end
end
