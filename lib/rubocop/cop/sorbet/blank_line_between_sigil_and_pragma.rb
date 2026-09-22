# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Sorbet
      # Detects blank lines between the `typed:` sigil comment and the
      # `frozen_string_literal:` magic comment. These two directives should be
      # adjacent at the top of the file — a blank line between them is a
      # formatting inconsistency with no semantic purpose.
      #
      # @example
      #   # bad
      #   # typed: strict
      #
      #   # frozen_string_literal: true
      #
      #   # good
      #   # typed: strict
      #   # frozen_string_literal: true
      class BlankLineBetweenSigilAndPragma < Base
        MSG = 'Remove the blank line between the typed: sigil and frozen_string_literal: pragma — they should be adjacent.'

        # The cop operates on the raw source lines, not the AST, because the
        # relevant lines are magic comments consumed by the parser/sorbet and
        # do not appear as AST nodes.
        def on_new_investigation
          lines = processed_source.lines
          return if lines.length < 2

          # Scan for the pattern: typed: line, one or more blank lines, frozen_string_literal: line.
          (0...(lines.length - 1)).each do |i|
            next unless typed_sigil?(lines[i])

            j = i + 1
            # Count consecutive blank lines after the sigil.
            blank_count = 0
            iterations_j = 0
            while j < lines.length && blank_line?(lines[j])
              iterations_j += 1
              break if iterations_j > 1_000

              blank_count += 1
              j += 1
            end

            # The line after the blanks must be frozen_string_literal:.
            next if blank_count.zero?
            next unless j < lines.length && frozen_pragma?(lines[j])

            add_offense(build_range(i, j), message: MSG)
          end
        end

        private

        TYPED_PATTERN = /\A#\s*typed:\s*\w+/
        FROZEN_PATTERN = /\A#\s*frozen_string_literal:\s*(true|false)/

        def typed_sigil?(line)
          TYPED_PATTERN.match?(line)
        end

        def frozen_pragma?(line)
          FROZEN_PATTERN.match?(line)
        end

        def blank_line?(line)
          line.strip.empty?
        end

        def build_range(sigil_index, frozen_index)
          # Offense range spans from the end of the typed: line to the start
          # of the frozen_string_literal: line — covering the blank gap.
          start_pos = line_offset(sigil_index) + processed_source.lines[sigil_index].length
          end_pos = line_offset(frozen_index)
          Parser::Source::Range.new(processed_source.buffer, start_pos, end_pos)
        end

        def line_offset(index)
          # Sum the byte lengths of all preceding lines (including newlines).
          processed_source.lines[0...index].sum(&:length) + index
        end
      end
    end
  end
end
