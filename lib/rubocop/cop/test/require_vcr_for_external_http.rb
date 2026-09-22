# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Test
      # Flags stub_request calls to non-localhost URLs in test files that don't
      # also use VCR.use_cassette or include WithoutVCR. Enforces a binary choice:
      # record with VCR, or explicitly opt out.
      class RequireVcrForExternalHttp < Base
        MSG = 'Use VCR.use_cassette or `include WithoutVCR` for external HTTP stubs.'

        def_node_matcher :stub_request?, <<~PATTERN
          (send nil? :stub_request (sym _) ...)
        PATTERN

        def_node_search :uses_vcr_or_without?, <<~PATTERN
          {
            (send (const nil? :VCR) :use_cassette ...)
            (send nil? :include (const nil? :WithoutVCR))
          }
        PATTERN

        def on_send(node)
          return unless stub_request?(node)
          return if uses_vcr_or_without?(processed_source.ast)
          return unless in_test_file?

          uri_node = node.arguments[1]
          return unless uri_node&.str_type?

          uri = uri_node.value
          return if localhost?(uri)
          return if allowed_pattern?(uri)

          add_offense(node)
        end

        private

        def in_test_file?
          processed_source.file_path.include?('/test/')
        end

        def localhost?(uri)
          uri.start_with?('http://localhost', 'http://127.0.0.1', 'http://example.test')
        end

        def allowed_pattern?(uri)
          allowed_patterns.any? { |pattern| uri.match?(pattern) }
        end

        def allowed_patterns
          cop_config['AllowedPatterns'] || []
        end
      end
    end
  end
end
