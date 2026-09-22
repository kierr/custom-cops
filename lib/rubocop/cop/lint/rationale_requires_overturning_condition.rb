# typed: true
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Ensures every RATIONALE comment includes an overturning condition.
      #
      # RATIONALE comments must end with "Would need X to reconsider" stating what
      # would need to change for the rationale to become wrong. Without this, future
      # reviewers cannot judge whether the rationale still holds.
      #
      # @example
      #
      #   # bad
      #   # RATIONALE: T.unsafe — external gem method lacks typed RBI.
      #
      #   # good
      #   # RATIONALE: T.unsafe — external gem method lacks typed RBI.
      #   #   Would need tapioca-generated RBI with typed method sig to reconsider.
      class RationaleRequiresOverturningCondition < Base
        MSG = 'RATIONALE comment must include an overturning condition: "Would need X to reconsider".'

        RATIONALE_PREFIX = /\A#\s*RATIONALE:/
        OVERTURNING_PATTERN = /Would need/

        def on_new_investigation
          rationale_blocks.each do |start_comment, combined_text|
            next if combined_text.match?(OVERTURNING_PATTERN)

            add_offense(start_comment, message: MSG)
          end
        end

        private

        # Builds a map of RATIONALE comment nodes to their combined text
        # (initial line + continuation comment lines). Continuation lines are
        # comment lines starting with # followed by extra whitespace (indented
        # continuations of the RATIONALE text).
        def extract_rationale_blocks
          blocks = {} # start_comment => combined text
          comments = processed_source.comments
          current_start = nil
          current_text = +''

          comments.each do |comment|
            text = comment.text

            if text.match?(RATIONALE_PREFIX)
              # Flush any previous block
              blocks[current_start] = current_text if current_start
              current_start = comment
              current_text = text
            elsif current_start && continuation_comment?(text)
              current_text += " #{text}"
            elsif current_start
              # Non-continuation — flush
              blocks[current_start] = current_text
              current_start = nil
              current_text = +''
            end
          end

          # Flush final block
          blocks[current_start] = current_text if current_start

          blocks
        end
        alias rationale_blocks extract_rationale_blocks

        def continuation_comment?(comment_text)
          # Continuation: "#   some text" — starts with # followed by whitespace
          # and more content, but not a new RATIONALE: or empty # line
          comment_text.match?(/\A#\s+\S/) &&
            !comment_text.match?(RATIONALE_PREFIX)
        end
      end
    end
  end
end
