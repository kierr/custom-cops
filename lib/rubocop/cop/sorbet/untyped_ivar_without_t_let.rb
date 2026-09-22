# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Sorbet
      # Detects bare instance variable assignments (`@ivar = value`) in files with
      # `typed: false` or `typed: true` sigils. At those levels, Sorbet infers
      # `T.untyped` for ivars that lack `T.let(...)`, silently propagating untyped
      # throughout the file. At `typed: strict` and above, Sorbet enforces `T.let`
      # natively, so this cop skips those files.
      #
      # @example
      #   # bad — in a typed: false or typed: true file
      #   @items = []
      #
      #   # good — in a typed: false or typed: true file
      #   @items = T.let([], T::Array[String])
      #
      #   # good — in a typed: strict or typed: strong file (Sorbet enforces natively)
      #   @items = []
      class UntypedIvarWithoutTLet < Base
        MSG = 'Use T.let for instance variable assignments at typed: false/true. At strict+, Sorbet enforces this natively.'

        # Sigil levels where Sorbet does NOT enforce T.let on ivars.
        UNENFORCED_SIGILS = %w[false true].freeze

        # Matches `T.let(...)` calls — `(send (const {nil? (cbase)} :T) :let ...)`.
        def_node_matcher :t_let_call?, <<~PATTERN
          (send (const {nil? (cbase)} :T) :let ...)
        PATTERN

        # Matches instance variable assignment: `@name = value`
        def_node_matcher :ivar_assignment?, <<~PATTERN
          (ivasgn _ $_)
        PATTERN

        # Sorbet's on_new_investigation callback fires once per file, before node
        # traversal. We use it to read the sigil level from the file's comments.
        def on_new_investigation
          super
          @sigil_level = extract_sigil_level
        end

        def on_ivasgn(node)
          return unless UNENFORCED_SIGILS.include?(@sigil_level)
          return unless (value = ivar_assignment?(node))
          return if t_let_call?(value)
          return if test_file?

          add_offense(node.loc.name, message: MSG)
        end

        private

        # Extracts the Sorbet typed strictness from the first comment line matching
        # `# typed: <level>`. Returns the level string (e.g. "true", "strict") or nil.
        def extract_sigil_level
          processed_source.comments.each do |comment|
            match = comment.text.match(/\A#\s*typed:\s*(\S+)\s*\z/)
            return match[1] if match
          end
          nil
        end

        def test_file?
          path = processed_source.file_path
          path.start_with?('test/', 'spec/') || path.include?('/test/') || path.include?('/spec/')
        end
      end
    end
  end
end
