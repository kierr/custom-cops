# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects keyword arguments with an underscore prefix in method definitions.
      # Adding an underscore prefix to a keyword argument changes its calling name,
      # so callers passing the original name get `ArgumentError: missing keyword: :_source`.
      #
      # Excludes `initialize` (constructor) and methods inside `private`/`protected`
      # blocks, since these are internal-only and callers cannot depend on them.
      # Keyword rest args (`**_opts`, `**_`) are excluded — the parameter name is
      # not visible to callers, so the prefix cannot break the calling API.      #
      # @example
      #   # bad — callers must pass `_source:` instead of `source:`
      #   def fetch(_source:, limit: 10)
      #     # ...
      #   end
      #
      #   # good — original keyword name preserved
      #   def fetch(source:, limit: 10)
      #     _ = source # explicitly discard if unused
      #   end
      class UnderscorePrefixBreaksCaller < Base
        MSG = 'Underscore-prefixed keyword argument `%<name>s` changes caller API. Use `_ = source` in the body instead.'

        # Track visibility context while traversing method definitions.
        def on_def(node)
          return if initialize_method?(node)
          return if inside_private_or_protected_block?(node)
          return if in_test_file?

          _ = check_arguments(node.arguments)
        end

        def on_defs(node)
          return if inside_private_or_protected_block?(node)
          return if in_test_file?

          _ = check_arguments(node.arguments)
        end

        private

        def check_arguments(args)
          args.each do |arg|
            # Keyword rest args (**_opts) don't change caller API — the name is
            # not visible to callers regardless of prefix.
            next unless arg.kwarg_type? || arg.kwoptarg_type?

            name = arg.name.to_s
            # Bare `_` is fine — it captures without renaming.
            next unless name.start_with?('_') && name.length > 1

            add_offense(arg.loc.name, message: format(MSG, name: name))
          end
        end

        def initialize_method?(node)
          node.method_name == :initialize
        end

        # Walk preceding siblings (and their ancestors) to find a bare
        # `private` / `protected` call. These appear as sibling `send` nodes
        # within a `begin` block, not as ancestors of the `def`.
        def inside_private_or_protected_block?(node)
          parent = node.parent
          return false unless parent&.begin_type?

          siblings = parent.children
          idx = siblings.index(node)
          return false unless idx

          siblings[0...idx].any? do |sib|
            visibility_send?(sib) || visibility_inside_module_function?(sib)
          end
        end

        def visibility_send?(node)
          node.send_type? && %i[private protected].include?(node.method_name)
        end

        # `module_function` also makes methods private at the class level.
        def visibility_inside_module_function?(node)
          node.send_type? && node.method_name == :module_function
        end

        def in_test_file?
          processed_source.file_path&.match?(/(_test\.rb|spec\.rb|test_.*\.rb)\z/)
        end
      end
    end
  end
end
