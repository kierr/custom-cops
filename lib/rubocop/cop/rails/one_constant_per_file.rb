# typed: strict
# frozen_string_literal: true

require_relative '../../custom_cops/zeitwerk_ignore_parser'

module RuboCop
  module Cop
    module Rails
      # Detects files in `app/` that define more than one class or struct at the
      # same nesting level. Multi-constant files are the root cause of Zeitwerk
      # ignore entries — each one requires a manual `.ignore()` call and explicit
      # require in `to_prepare`. Define one top-level constant per file instead.
      #
      # @example
      #   # bad — two classes at root level
      #   class FooError < StandardError; end
      #   class BarError < StandardError; end
      #
      #   # good — single class per file
      #   class FooError < StandardError; end
      #
      #   # good — single module wrapping single class
      #   module Types
      #     class Foo; end
      #   end
      #
      class OneConstantPerFile < Base
        MSG = 'Define one class/struct per file. Multi-constant files require Zeitwerk ignore entries and explicit requires.'

        def on_new_investigation
          file_path = processed_source.file_path
          return unless file_path.include?('/app/')
          return if ignored_file?(file_path)

          class_nodes = extract_class_nodes(processed_source.ast)
          return unless class_nodes.size > 1

          # Flag the second and subsequent definitions.
          class_nodes[1..].each { |node| add_offense(node) }
        end

        def ignored_file?(file_path)
          pwd = Dir.pwd
          relative = file_path.delete_prefix("#{pwd}/")
          ::RuboCop::Cop::CustomCops::ZeitwerkIgnoreParser.ignored_paths.any? do |ignored|
            relative == ignored || relative.start_with?("#{ignored}/")
          end
        end

        private

        # Returns class nodes at the relevant nesting level. If the file has a
        # single top-level module wrapper (either as the root AST node or as its
        # only child), counts classes inside that module. Otherwise counts
        # top-level classes directly.
        def extract_class_nodes(ast)
          return [] unless ast

          # Case 1: the entire file is a single module definition (most common).
          return unwrap_body_classes(ast) if ast.module_type?

          children = ast.children

          # Case 2: root has a single module child (e.g. wrapped in a begin node).
          # AST children can include non-node types (Symbols, Strings, etc.) from
          # statements like `require_relative`; guard with is_a? before type checks.
          module_nodes = children.select { |c| c.is_a?(RuboCop::AST::Node) && c.module_type? }
          return unwrap_body_classes(module_nodes.first) if single_module_only?(module_nodes, children)

          children.select { |c| c.is_a?(RuboCop::AST::Node) && c.class_type? }
        end

        # True when the root children contain exactly one module and no top-level classes.
        def single_module_only?(module_nodes, children)
          module_nodes.size == 1 &&
            children.none? { |c| c.is_a?(RuboCop::AST::Node) && c.class_type? }
        end

        # A module's body is either a single node (one statement) or a begin
        # node wrapping multiple statements.
        def unwrap_body_classes(module_node)
          body = module_node&.children&.last
          return [] unless body

          if body.begin_type?
            body.children.select { |c| c&.class_type? }
          elsif body.class_type?
            [body]
          else
            []
          end
        end
      end
    end
  end
end
