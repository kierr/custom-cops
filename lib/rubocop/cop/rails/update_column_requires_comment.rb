# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Detects `update_column` / `update_columns` calls that lack a preceding
      # comment explaining why bypassing validations, callbacks, and PaperTrail
      # is intentional. These methods skip all AR lifecycle hooks — every call
      # site must document the bypass rationale.
      #
      # The cop only fires in `app/` — lib/ and test/ are exempt because test
      # fixtures and low-level library code have different justification
      # requirements.
      #
      # Methods whose name contains "update_column" or "transition_status" are
      # treated as wrapper methods that centralize the bypass and are exempt.
      #
      # @example
      #   # bad — no justification comment
      #   entity.update_column(:status, 'active')
      #
      #   # good — comment with justification keyword
      #   # counter cache reconciliation — bypass AR callbacks for performance
      #   entity.update_column(counter_column, actual)
      #
      #   # good — wrapper method (name contains "update_column")
      #   def force_update_column(attrs)
      #     update_columns(attrs)
      #   end
      class UpdateColumnRequiresComment < Base
        MSG = 'Add a comment explaining why `update_column` bypasses validations, callbacks, and PaperTrail. ' \
              'Keywords: bypass, intentionally, skip, RATIONALE, avoid, performance, safe because, counter cache.'

        # Keywords that indicate the developer has consciously chosen to bypass AR lifecycle.
        JUSTIFICATION_PATTERNS = /bypass|intentionally|intentional|skip|RATIONALE|avoid|performance|safe\s+because|counter\s+cache/i

        # How many source lines above the call to scan for a justification comment.
        LOOKBACK_LINES = 5

        # Method name substrings that indicate a centralized bypass wrapper.
        WRAPPER_NAME_PATTERNS = %w[update_column transition_status].freeze

        def_node_matcher :update_column_call?, <<~PATTERN
          (send _ {:update_column :update_columns} ...)
        PATTERN

        def on_send(node)
          return unless update_column_call?(node)
          return unless app_file?
          return if inside_wrapper_method?(node)
          return if justified?(node)

          add_offense(node.loc.selector, message: MSG)
        end

        private

        def app_file?
          filename = processed_source.file_path
          filename.start_with?('app/') || filename.include?('/app/')
        end

        def inside_wrapper_method?(node)
          def_node = node.each_ancestor(:def).first
          return false unless def_node

          method_name = def_node.method_name.to_s
          WRAPPER_NAME_PATTERNS.any? { |pattern| method_name.include?(pattern) }
        end

        def justified?(node)
          call_line = node.loc.expression.line
          start_line = [1, call_line - LOOKBACK_LINES].max
          source_lines = processed_source.lines

          # Include the call line itself to catch inline trailing comments.
          (start_line..call_line).each do |line_num|
            line = source_lines[line_num - 1]
            next unless line
            next unless line.include?('#')

            return true if JUSTIFICATION_PATTERNS.match?(line)
          end

          false
        end
      end
    end
  end
end
