# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Test
      class RequireExpandedTestHelper < Base
        MSG = 'Use `require File.expand_path(..., __dir__)` instead of bare `require "test_helper"` in test files.'

        EXCLUDED_BASENAMES = %w[test_helper.rb vcr_setup.rb application_system_test_case.rb].freeze

        def_node_matcher :bare_test_helper_require?, <<~PATTERN
          (send nil? :require (str "test_helper"))
        PATTERN

        def on_send(node)
          return unless bare_test_helper_require?(node)
          return if EXCLUDED_BASENAMES.include?(File.basename(processed_source.file_path))

          add_offense(node)
        end
      end
    end
  end
end
