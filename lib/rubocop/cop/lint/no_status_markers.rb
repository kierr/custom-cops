# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Bans `# STATUS:` comments in Ruby files. The manual unused-code taxonomy
      # is replaced by automated dead-code detection (`scripts/dead-code-scan`).
      # STATUS markers are no longer the mechanism — the scanner is.
      class NoStatusMarkers < Base
        MSG = 'STATUS markers are banned. Use `scripts/dead-code-scan` for dead code detection.'

        def on_new_investigation
          processed_source.comments.each do |comment|
            next unless /#\s*STATUS:/.match?(comment.text)

            add_offense(comment, message: MSG)
          end
        end
      end
    end
  end
end
