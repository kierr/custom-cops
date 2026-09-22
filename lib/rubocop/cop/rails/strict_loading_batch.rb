# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Flags `strict_loading(false)` calls in test files that lack an explanatory
      # comment. In the test environment `strict_loading_by_default` is `true`.
      # Batch queries touching associations need `strict_loading(false)` to avoid
      # silently swallowed errors, but every call site must document why.
      #
      # This cop ensures the suppression is intentional and visible.
      #
      # @example
      #   # bad — no explanation
      #   Person.strict_loading(false).where(...)
      #
      #   # good — documented reason
      # Person.strict_loading(false).where(...) # RATIONALE: batch scan loads associations across records
      #
      #   # good — any inline comment
      #   records = Org.strict_loading(false).find_each # bulk association access for export
      class StrictLoadingBatch < Base
        MSG = 'Add a comment explaining why `strict_loading(false)` is needed. Test env has strict_loading_by_default=true.'

        def_node_matcher :strict_loading_false?, <<~PATTERN
          (send _ :strict_loading (false))
        PATTERN

        def on_send(node)
          return unless strict_loading_false?(node)

          # Check if there's a comment on the same line
          line = node.loc.expression.line
          source_line = processed_source.lines[line - 1]
          return if source_line.include?('#')

          add_offense(node.loc.selector, message: MSG)
        end
      end
    end
  end
end
