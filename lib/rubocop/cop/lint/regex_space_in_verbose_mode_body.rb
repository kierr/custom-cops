# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects literal spaces in the body of verbose-mode regexes (`/x` flag).
      # In `/x` mode, unescaped literal spaces are ignored by the regex engine —
      # `/REGISTERED AGENT/x` matches "REGISTEREDAGENT", not "REGISTERED AGENT".
      # Use `[ ]` or `\ ` for intentional literal space matching.
      #
      # Complements `Lint::RegexSpaceInVerboseMode`, which flags literal spaces
      # in non-verbose regexes. This cop handles the verbose-mode inverse: spaces
      # that the developer likely intended as literal but `/x` silently discards.
      #
      # @example
      #
      #   # bad — space is ignored in /x mode, matches "REGISTEREDAGENT"
      #   /REGISTERED AGENT/x
      #   /VICE PRESIDENT/ix
      #
      #   # good — explicit literal space in character class
      #   /REGISTERED[ ]AGENT/x
      #
      #   # good — escaped literal space
      #   /REGISTERED\ AGENT/x
      #
      #   # good — whitespace shorthand
      #   /REGISTERED\sAGENT/x
      #
      #   # good — non-verbose regex (handled by RegexSpaceInVerboseMode)
      #   /REGISTERED AGENT/
      #
      class RegexSpaceInVerboseModeBody < Base
        MSG = 'Literal space in `/x` regex is ignored — use `[ ]` or `\\ ` for intentional space.'

        # Characters that indicate the space is formatting between groups,
        # not part of a multi-word token.
        FORMATTING_CHARS = %w[| ( )].freeze

        # Scan the regex source string for unescaped literal spaces between
        # non-space characters. Spaces inside character classes `[...]` are
        # intentional and excluded. So are escaped spaces (`\ `) and `\s`.
        #
        # The approach walks the source character-by-character to correctly
        # handle character class boundaries and escape sequences.
        def on_regexp(node)
          return unless verbose_mode?(node)

          source = extract_source(node)
          return if source.empty?
          return if find_ignored_spaces(source).empty?

          # One offense per regex is sufficient — the message describes the
          # general problem. No autocorrect: rebuilding the literal from the
          # extracted string content loses the `\/`-vs-`[/]` distinction and
          # mislocates the closing delimiter when the body contains escaped
          # slashes, so a mechanical re-escape corrupts the regex.
          add_offense(node)
        end

        private

        def verbose_mode?(node)
          regopt = node.children.last
          regopt&.children&.include?(:x)
        end

        # Collect the literal string content from str children of the regexp.
        # Dynamic interpolation (dstr) segments are skipped — we can only
        # analyze static portions.
        def extract_source(node)
          parts = []
          node.children.each do |child|
            next unless child&.type == :str

            parts << child.value
          end
          parts.join
        end

        # Walk the source string character by character, tracking whether we
        # are inside a character class `[...]`. Unescaped spaces outside
        # character classes are flagged.
        def find_ignored_spaces(source)
          offenses = []
          in_char_class = false
          idx = 0

          while idx < source.length
            ch = source[idx]

            if ch == '\\' && idx + 1 < source.length
              # Skip escaped character (e.g., \s, \ , \\)
              idx += 2
              next
            end

            if ch == '['
              in_char_class = true
              idx += 1
              next
            end

            if ch == ']'
              in_char_class = false
              idx += 1
              next
            end

            if ch == ' ' && !in_char_class && space_between_content?(source, idx)
              # Only flag if the space is between non-space, non-pipe,
              # non-parenthesis characters (i.e., it looks like part of
              # a multi-word token, not formatting between groups).
              offenses << idx
            end

            idx += 1
          end

          offenses
        end

        # Check that the space sits between content characters on both sides.
        # A space at the very start/end or adjacent to `|`, `(`, `)` is
        # formatting, not part of a multi-word token.
        def space_between_content?(source, idx)
          prev_ch = idx.positive? ? source[idx - 1] : nil
          next_ch = idx + 1 < source.length ? source[idx + 1] : nil

          return false unless prev_ch && next_ch
          return false if formatting_boundary?(prev_ch)
          return false if formatting_boundary?(next_ch)

          true
        end

        def formatting_boundary?(ch)
          FORMATTING_CHARS.include?(ch)
        end
      end
    end
  end
end
