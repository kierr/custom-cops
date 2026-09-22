# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Test
      # Flags VCR.turn_off!/VCR.turn_on! calls in test files where the enclosing
      # class doesn't include WithoutVCR. Use the helper module instead of manual
      # turn_off/turn_on pairs.
      class RequireWithoutVcrHelper < Base
        MSG = 'Use `include WithoutVCR` instead of manual VCR.turn_off!/turn_on! calls.'

        def_node_matcher :vcr_turn_off?, <<~PATTERN
          (send (const nil? :VCR) :turn_off! ...)
        PATTERN

        def_node_search :includes_without_vcr?, <<~PATTERN
          (send nil? :include (const nil? :WithoutVCR))
        PATTERN

        def on_send(node)
          return unless vcr_turn_off?(node)
          return if includes_without_vcr?(processed_source.ast)
          return unless in_test_file?

          add_offense(node)
        end

        private

        def in_test_file?
          processed_source.file_path.include?('/test/')
        end
      end
    end
  end
end
