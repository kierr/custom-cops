# typed: strict
# frozen_string_literal: true

require 'open3'

module RuboCop
  module Cop
    module Lint
      # Detects module definitions in `app/` or `lib/` that are never included,
      # extended, or prepended anywhere in the project. Dead modules typically
      # result from incomplete decompositions where an extraction was started but
      # the consuming side was never connected.
      #
      # The cop performs a project-wide grep for `include`/`extend`/`prepend` calls
      # referencing each module's short name. Short-name matching is deliberate:
      # Zeitwerk autoloading makes full constant paths context-dependent, and
      # short-name matching catches both `include Foo` and `include Namespace::Foo`.
      #
      # Modules that define class methods (`def self.x`), use `extend self`, or
      # declare `module_function` are assumed to be standalone utilities and are
      # not flagged — they are called directly, not mixed in.
      #
      # @example
      #
      #   # bad — module never referenced via include/extend/prepend
      #   module StrictPagination
      #     def validate_per_page; end
      #   end
      #
      #   # good — referenced via include
      #   module StrictPagination
      #     def validate_per_page; end
      #   end
      #   # elsewhere:
      #   include StrictPagination
      class ModuleNeverIncluded < Base
        MSG = 'Module `%<module_name>s` is never included, extended, or prepended. Wire it in or remove it if the decomposition was abandoned.'

        # Recurse into module bodies to find all module definitions in the file.
        def_node_search :module_definitions, <<~PATTERN
          (module ...)
        PATTERN

        # Match include/extend/prepend calls bearing the module name at any
        # constant nesting depth (e.g., `include Foo`, `include NS::Foo`).
        def_node_search :include_like_call?, <<~PATTERN
          (send _ {:include :extend :prepend} (const ... %1))
        PATTERN

        def on_new_investigation
          file_path = processed_source.file_path
          return unless in_scoped_directory?(file_path)

          ast = processed_source.ast
          return unless ast

          module_definitions(ast).each do |mod_node|
            _ = check_module(mod_node, file_path)
          end
        end

        private

        def in_scoped_directory?(file_path)
          file_path.include?('/app/') || file_path.include?('/lib/')
        end

        def check_module(mod_node, file_path)
          module_name = extract_module_name(mod_node)
          return unless module_name
          return if module_name.length < 3
          return if standalone_module?(mod_node)
          return if module_used_in_project?(module_name, file_path)

          loc = mod_node.loc
          add_offense(loc.name, message: format(MSG, module_name: module_name))
        end

        # Extract the short name of the module from its AST node.
        # `module Foo::Bar` yields "Bar"; `module Foo` yields "Foo".
        def extract_module_name(mod_node)
          name_node = mod_node.children.first
          return nil unless name_node

          if name_node.const_type?
            # (const (const nil? :Foo) :Bar) -> :Bar
            name_node.children.last.to_s
          else
            name_node.to_s
          end
        end

        # A module is not a mixin candidate if it defines none of its own
        # instance methods — it is a namespace container holding only nested
        # classes/modules/constants. A module with class methods or extend self
        # / module_function is a standalone utility. Either way it is not meant
        # for mixin, so it is not "dead" even if never included.
        def standalone_module?(mod_node)
          body = mod_node.children.last
          return false unless body

          return true unless defines_instance_methods?(body)

          contains_standalone_pattern?(body)
        end

        # True if the module declares an instance method of its own (a `def`,
        # not `def self.x`). Does NOT descend into nested class/module bodies or
        # `class << self` (sclass): a namespace module's nested job class defines
        # `def perform`, and a `class << self` block defines singleton methods,
        # but neither is an instance method of the surrounding module.
        # Stopping at class/module/sclass boundaries is what distinguishes a mixin
        # (own `def`s) from a namespace or class-method utility.
        def defines_instance_methods?(node)
          return false unless node.is_a?(RuboCop::AST::Node)

          return true if node.def_type?
          return false if node.class_type? || node.module_type? || node.sclass_type?

          node.children.any? { |child| defines_instance_methods?(child) }
        end

        def contains_standalone_pattern?(node)
          # def self.x — class-level method
          return true if node.defs_type?

          # extend self / module_function — standalone utility intent
          if node.send_type?
            method_name = node.method_name
            return true if %i[extend module_function].include?(method_name)
          end

          node.children.any? do |child|
            next false unless child.is_a?(RuboCop::AST::Node)

            contains_standalone_pattern?(child)
          end
        end

        # Search the project for include/extend/prepend of the module's short name.
        # Uses git grep for speed on large codebases; falls back to grep -R.
        def module_used_in_project?(module_name, source_file)
          project_root = detect_project_root(source_file)
          # Cannot determine project root; assume used to avoid false positives.
          return true unless project_root

          pattern = /(include|extend|prepend)\s+(::)?(\w+::)*#{Regexp.escape(module_name)}\b/

          git_grep?(project_root, pattern) || system_grep?(project_root, pattern)
        end

        def detect_project_root(source_file)
          dir = File.dirname(source_file)
          max_depth = 20

          max_depth.times do
            return dir if Dir.exist?(File.join(dir, 'app')) && File.exist?(File.join(dir, 'Gemfile'))
            return dir if Dir.exist?(File.join(dir, 'lib')) && File.exist?(File.join(dir, 'Gemfile'))

            parent = File.dirname(dir)
            return nil if parent == dir # filesystem root

            dir = parent
          end

          nil
        end

        def git_grep?(project_root, pattern)
          _out, status = Open3.capture2(
            'git', '-C', project_root, 'grep', '-qE', pattern.source, '--', '*.rb',
            chdir: project_root,
            err: File::NULL
          )
          status.success?
        rescue StandardError => e
          warn("module_never_included: git grep failed: #{e.class}: #{e.message}")
          false
        end

        def system_grep?(project_root, pattern)
          _out, status = Open3.capture2('grep', '-rqE', pattern.source, '--include=*.rb', project_root, err: File::NULL)
          status.success?
        rescue StandardError => e
          warn("module_never_included: system grep failed: #{e.class}: #{e.message}")
          # Cannot search; assume used to avoid false positives.
          true
        end
      end
    end
  end
end
