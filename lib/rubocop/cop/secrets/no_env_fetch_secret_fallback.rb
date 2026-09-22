# typed: strict
# frozen_string_literal: true

# incomplete RBI coverage (custom methods like env_fetch_with_fallback? not in RBIs).
# All 38 errors are 7003 "method does not exist". See AGENTS.md rule #1.

module RuboCop
  module Cop
    module Secrets
      class NoEnvFetchSecretFallback < Base
        MSG = 'Do not provide a non-blank fallback for secret environment variables. They should fail loudly when missing.'

        SECRET_PATTERNS = %w[SECRET KEY TOKEN PASSWORD CREDENTIAL PRIVATE SIGNING].freeze

        def_node_matcher :env_fetch_with_fallback?, <<~PATTERN
          (send (const {nil? (cbase)} :ENV) :fetch (str _) ...)
        PATTERN

        def on_send(node)
          return unless env_fetch_with_fallback?(node)

          key_node = node.arguments.first
          return unless key_node.str_type?

          key = key_node.value
          # Segment match, not substring: SECRET_PATTERNS must equal a whole
          # underscore-delimited segment. Substring matching false-positived on
          # names like FEATURE_MAX_TOKENS, where TOKEN is a fragment of TOKENS
          # — not a secret.
          key_segments = key.upcase.split('_')
          return unless SECRET_PATTERNS.any? { |pattern| key_segments.include?(pattern) }

          # Check positional fallback
          if node.arguments.size >= 2
            fallback = node.arguments[1]
            return if fallback.nil_type?
            return if fallback.str_type? && fallback.value.empty?

            add_offense(fallback)
          end

          # Check block-form fallback: ENV.fetch('KEY') { 'default' }
          return unless node.block_node

          block_body = node.block_node.body
          return unless block_body && !(block_body.str_type? && block_body.value.empty?) && !block_body.nil_type?

          add_offense(block_body)
        end
      end
    end
  end
end
