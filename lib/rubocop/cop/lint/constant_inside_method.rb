# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # DECISION: this cop is disabled in config/default.yml and must not be enabled.
      # RATIONALE: structurally unwireable — its target (`CONST = x` inside a method
      # body) is a Ruby parse-time SyntaxError ("dynamic constant assignment"), so a
      # file with a real offense never parses and the cop never runs on it. Audit #1198:
      # 0 real / 20 false positive (hash rockets, heredoc contents, class-level
      # constants misclassified by the line-based depth tracker). Would need a genuinely
      # different target (e.g. explicit-receiver constant mutation `Object::FOO =`, or
      # `const_set`) to reconsider — left disabled as a stub.
      class ConstantInsideMethod < Base
        MSG = 'Do not assign constants inside a method body. Move the constant to module/class level.'

        # UPPER_SNAKE_CASE identifier followed by = with optional spacing.
        CONSTANT_ASSIGNMENT_RE = /\A\s*([A-Z][A-Z0-9_]*)\s*=/

        # Matches def / def self.x — method definitions (not class/module).
        DEF_RE = /\bdef\b/

        # Matches class or module declarations.
        CLASS_MODULE_RE = /\b(class|module)\b/

        def on_new_investigation
          return if processed_source.nil?

          method_depth = 0
          class_depth = 0

          processed_source.lines.each_with_index do |line, idx|
            stripped = line.strip
            next if stripped.start_with?('#')

            method_depth, class_depth = update_depth(stripped, method_depth, class_depth)
            next unless method_depth.positive?
            next unless (match = CONSTANT_ASSIGNMENT_RE.match(line))
            next if inside_string_literal?(line, match.begin(1))

            add_constant_offense(processed_source, line, idx)
          end
        end

        private

        # Heuristic: an odd count of unescaped double quotes before the match
        # position suggests the constant name sits inside a string literal.
        def inside_string_literal?(line, position)
          line[0...position].count('"').odd?
        end

        # Track nesting: method_depth > 0 means inside a def body.
        # class/module depth tracked separately so class-level constants are not flagged.
        def update_depth(stripped, method_depth, class_depth)
          if DEF_RE.match?(stripped)
            [method_depth + 1, class_depth]
          elsif CLASS_MODULE_RE.match?(stripped)
            [method_depth, class_depth + 1]
          elsif stripped == 'end'
            method_depth.positive? ? [method_depth - 1, class_depth] : [method_depth, [class_depth - 1, 0].max]
          else
            [method_depth, class_depth]
          end
        end

        def add_constant_offense(source, line, idx)
          line_range = source.buffer.line_range(idx + 1)
          range = Parser::Source::Range.new(source.buffer, line_range.begin_pos + line.index(/\S/),
                                            line_range.begin_pos + line.lstrip.length)
          add_offense(range, message: MSG)
        end
      end
    end
  end
end
