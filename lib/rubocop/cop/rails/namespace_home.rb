# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Enforces that a namespace has a single authoritative directory.
      # A namespace that exists in `app/models/`, `app/services/`, etc. should
      # not also have files in `app/lib/` — those files belong in the namespace's
      # canonical directory.
      #
      # Similarly, a namespace rooted in `lib/` should not also appear in `app/`
      # unless it's a RuboCop cop (tooling, not domain code).
      #
      # @example
      #
      #   # bad — namespace exists in app/models/billing/ and app/services/billing/
      #   # but also has a stray file in app/lib/billing/
      #   app/lib/billing/invoice_builder.rb  # ← flagged
      #
      #   # good — namespace files exist in the canonical directory
      #   app/models/billing/runner.rb
      #   app/services/billing/session/processor.rb
      #
      #   # good — app/lib/ has its own unique namespace
      #   app/lib/http/config.rb
      #   app/lib/http/client.rb
      #
      class NamespaceHome < Base
        MSG = 'Namespace `%<name>s` already exists in %<homes>s. Move this file to the namespace\'s canonical home instead of app/lib/.'

        # app/ subdirectories that represent a canonical directory for a namespace.
        CANONICAL_DIRS = %w[models services controllers consumers jobs mailers helpers channels].freeze

        def on_new_investigation
          file_path = processed_source.file_path
          return unless file_path.include?('/app/lib/')

          # Extract snake_case namespace directory: app/lib/billing/invoice_builder.rb → "billing"
          namespace_dir = file_path[%r{/app/lib/([^/]+)/}, 1]
          return unless namespace_dir

          # Convert to CamelCase module name for the message.
          module_name = namespace_dir.split('_').map(&:capitalize).join

          app_root = file_path[%r{\A(.*?/app)/lib/}, 1]
          return unless app_root

          homes = CANONICAL_DIRS.select do |dir|
            dir_glob(File.join(app_root, dir, namespace_dir, '**', '*.rb')).any?
          end
          return if homes.empty?

          # Flag only ACTUAL duplication: a leaf constant defined in this lib file
          # that is also defined in a canonical directory. A shared namespace module
          # whose leaf class is unique to app/lib is not a duplicate, even when the
          # namespace also exists in app/. Comparing leaf FQNs (not the bare
          # namespace, which every file in it reopens) is what suppresses that
          # false positive.
          lib_leaves = leaf_fqns(defined_fqns(processed_source.ast))
          return unless home_defines_duplicate_leaf?(lib_leaves, app_root, namespace_dir, homes)

          mod_node = find_module_node(processed_source.ast)
          loc = mod_node&.loc&.name || processed_source.buffer.source_range

          add_offense(
            loc,
            message: format(MSG, name: module_name, homes: homes.map { |d| "app/#{d}/" }
                                                                .join(', '))
          )
        end

        private

        def dir_glob(pattern)
          Dir.glob(pattern)
        end

        # Whether any canonical-home file defines a leaf FQN also defined in the
        # lib file. Routes home-file reads through #fqns_in_file so tests can stub
        # them without files on disk.
        def home_defines_duplicate_leaf?(lib_leaves, app_root, namespace_dir, homes)
          homes.any? do |dir|
            dir_glob(File.join(app_root, dir, namespace_dir, '**', '*.rb')).any? do |path|
              lib_leaves.intersect?(leaf_fqns(fqns_in_file(path)))
            end
          end
        end

        # Fully-qualified constant names defined in the given AST, with nesting
        # resolved (module Http; class Client → "Http", "Http::Client").
        def defined_fqns(ast)
          fqns = []
          collect_fqns(ast, [], fqns)
          fqns
        end

        def collect_fqns(node, scope, fqns)
          return unless node.is_a?(AST::Node)

          if node.module_type? || node.class_type?
            name = const_path(node.children.first)
            namespace = name.split('::')
            full = name.include?('::') ? name : (scope + namespace).join('::')
            fqns << full
            body = node.module_type? ? node.children[1] : node.children[2]
            collect_fqns(body, name.include?('::') ? namespace : scope + namespace, fqns)
          else
            node.children.each { |child| collect_fqns(child, scope, fqns) }
          end
        end

        # Dotted constant path of a const node: s(:const, s(:const,nil,:Http),:Client) → "Http::Client".
        def const_path(node)
          return '' unless node&.const_type?

          base = node.children.first
          leaf = node.children[1].to_s
          base.nil? ? leaf : "#{const_path(base)}::#{leaf}"
        end

        # FQNs that are not a namespace prefix of another FQN in the same set —
        # the actual leaf constants, with the reopened namespace module excluded.
        def leaf_fqns(fqns)
          fqns.reject { |fqn| fqns.any? { |other| other != fqn && other.start_with?("#{fqn}::") } }
        end

        # FQNs defined in a file on disk. Stubbed in tests so home files need not exist.
        def fqns_in_file(path)
          source = File.read(path)
          ast = RuboCop::AST::ProcessedSource.new(source, ruby_version_for_ast).ast
          defined_fqns(ast)
        rescue StandardError => e
          # RATIONALE: RuboCop cop code runs in the linter process where no SemanticLogger
          # is booted. A read or parse failure over a canonical-home file means we cannot
          # compare leaves — treating it as "no duplicate defined" lets the investigation
          # finish without crashing the whole RuboCop run. Would need RuboCop to expose a
          # structured warning channel to reconsider.
          warn("Rails/NamespaceHome: failed to read FQNs from #{path}: #{e.class}: #{e.message}")
          []
        end

        # RUBY_VERSION is "3.4.8" — ProcessedSource expects a Numeric (e.g. 3.4).
        def ruby_version_for_ast
          Float(RUBY_VERSION.split('.').first(2).join('.'))
        end

        def find_module_node(ast)
          return ast if ast&.module_type?
          return nil unless ast

          ast.children.each do |child|
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
