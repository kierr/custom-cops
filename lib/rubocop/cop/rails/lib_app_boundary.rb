# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Enforces the `lib/` vs `app/` boundary: code in `lib/` must have zero
      # app dependencies. A namespace that exists in both `lib/` and `app/`
      # almost certainly violates this — the `lib/` version either depends on
      # something in `app/`, or the split is incoherent.
      #
      # Flags files in `lib/` whose top-level namespace directory also appears
      # under any `app/` subdirectory. Excludes `lib/rubocop/` (tooling that
      # legitimately references app namespaces for linting).
      #
      # @example
      #
      #   # bad — lib/myproj/infra/ exists AND app/lib/infra/ exists
      #   # (or app/models/infra/, app/services/infra/, etc.)
      #   lib/myproj/infra/redis.rb  # ← flagged
      #
      #   # good — lib/rubocop/ cops reference app namespaces for linting
      #   lib/rubocop/cop/browserops/no_direct_transport.rb
      #
      #   # good — lib/ namespace with no app/ counterpart
      #   lib/generators/word_pair/word_pair_generator.rb
      #
      class LibAppBoundary < Base
        MSG = 'Namespace `%<name>s` exists in both lib/ and app/. ' \
              'lib/ code must have zero app dependencies — move this to app/ ' \
              'or merge with the app/ version.'

        # lib/ subdirectories that legitimately reference app namespaces.
        EXEMPT_LIB_DIRS = %w[rubocop tasks templates].freeze

        def on_new_investigation
          file_path = processed_source.file_path
          return unless file_path.include?('/lib/')

          # Skip exempt tooling directories.
          lib_segment = file_path[%r{/lib/([^/]+)/}, 1]
          return if EXEMPT_LIB_DIRS.include?(lib_segment)

          # Walk up to find the top-level namespace directory under lib/.
          # lib/myproj/infra/redis.rb → check if "myproj" or "infra" exists in app/.
          # We check each segment: the first one that matches an app/ directory is the violation.
          lib_path = file_path[%r{\A(.*?/lib/)}, 1]
          return unless lib_path

          relative = file_path.delete_prefix(lib_path)
          segments = relative.split('/')

          app_root = file_path[%r{\A(.*?)/lib/}, 1]
          return unless app_root

          segments.each_with_index do |segment, idx|
            next if idx.zero? && segment == 'myproj' # project gem namespace, skip

            # Check if this segment exists as a directory in any app/ subdirectory.
            found = app_dir_has_namespace?(app_root, segment)
            next unless found

            module_name = segment.split('_').map(&:capitalize).join

            # Skip if the lib file has no app/ dependencies — the dependency
            # direction is correct (app → lib) and no boundary violation exists.
            return unless has_app_dependencies?

            add_offense(find_module_loc || processed_source.buffer.source_range, message: format(MSG, name: module_name))
            return # One offense per file is enough.
          end
        end

        private

        def app_dir_has_namespace?(app_root, snake_name)
          Dir.glob(File.join(app_root, 'app', '*', snake_name)).any? { |path| File.directory?(path) }
        end

        # True when the lib file contains require/require_relative calls,
        # indicating it depends on other code rather than being self-contained.
        # Self-contained lib modules have correct dependency direction (app → lib).
        def has_app_dependencies?
          ast = processed_source.ast
          return true unless ast # No AST — conservatively flag.

          ast.each_node(:send).any? do |node|
            %i[require require_relative].include?(node.method_name)
          end
        end

        def find_module_loc
          ast = processed_source.ast
          return nil unless ast

          mod = find_module_node(ast)
          mod&.loc&.name
        end

        def find_module_node(node)
          return node if node&.module_type?
          return nil unless node.is_a?(AST::Node)

          node.children.each do |child|
            next unless child.is_a?(AST::Node)

            found = find_module_node(child)
            return found if found
          end
          nil
        end
      end
    end
  end
end
