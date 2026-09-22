# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects regex literals containing multi-word sequences with literal spaces
      # that match fixed text (titles, labels, status strings). A literal space in a
      # regex matches only ASCII space (0x20), not tab or newline. When matching scraped
      # or user-supplied text, `\s` or `[ ]` is more robust — `\s` matches all
      # whitespace, `[ ]` makes the space visually intentional.
      #
      # In verbose regexes (`/x` flag), literal spaces are ignored entirely (used for
      # readability), so this cop does not flag regexes with the `x` option.
      #
      # Regexes already containing `[ ]` or `\s` at the match site are excluded.
      #
      # @example
      #
      #   # bad — literal space only matches ASCII space
      #   /REGISTERED AGENT|STATUTORY AGENT/
      #   /VICE PRESIDENT/
      #
      #   # good — explicit whitespace class
      #   /REGISTERED\sAGENT|STATUTORY\sAGENT/
      #   /VICE\sPRESIDENT/
      #
      #   # good — intentional space in character class
      #   /REGISTERED[ ]AGENT/
      #
      #   # good — verbose mode, spaces are formatting only
      #   /REGISTERED AGENT/x
      #
      #   # good — single words, no inter-word spaces
      #   /AGENT|MANAGER|DIRECTOR/
      #
      class RegexSpaceInVerboseMode < Base
        MSG = 'Use `\\s` or `[ ]` instead of literal space in regex matching fixed text — literal space does not match tab or newline.'

        # Pattern: two or more uppercase words separated by a literal space,
        # where neither side uses [ ] or \s. Matches sequences like
        # "REGISTERED AGENT", "VICE PRESIDENT", "BUSINESS ASSOCIATE".
        # Excludes already-escaped spaces (\ ) and character-class spaces ([ ]).
        MULTI_WORD_SPACE = /[A-Z][A-Z]+ (?=[A-Z])/

        def on_regexp(node)
          return if verbose_mode?(node)

          each_str_child(node) do |str_content|
            next unless contains_multi_word_space?(str_content)

            add_offense(node)
            return # one offense per regex is sufficient
          end
        end

        private

        def verbose_mode?(node)
          # The last child of a regexp node is regopt. Its children are the
          # option symbols (:i, :x, :m, etc.).
          regopt = node.children.last
          regopt&.children&.include?(:x)
        end

        def each_str_child(node)
          # Regex body is a sequence of str/dstr/escape nodes before the
          # trailing regopt. Yield the string content of each str node.
          node.children.each do |child|
            next unless child&.type == :str

            yield child.value
          end
        end

        def contains_multi_word_space?(str)
          # Exclude strings where the space is inside a character class [ ]
          # or preceded by a backslash (escaped space \ ).
          return false if str.include?('[ ]')
          return false if str.include?('\\ ')
          return false if str.include?('\\s')

          MULTI_WORD_SPACE.match?(str)
        end
      end
    end
  end
end
