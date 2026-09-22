# typed: strict
# frozen_string_literal: true

require_relative '../../custom_cops/comment_window'

module RuboCop
  module Cop
    module Sorbet
      # Enforces that T.untyped and T.unsafe have justification comments.
      # For T.unsafe, the justification must name a metaprogramming pattern
      # or the argument must be `self`. T.unsafe is a metaprogramming bypass
      # only (Sorbet docs: troubleshooting.md) — not a type-coverage tool.
      class UntypedRequiresJustification < Base
        include ::RuboCop::Cop::CustomCops::CommentWindow

        MSG_UNTYPED = 'T.untyped requires a justification comment (RATIONALE:, DYNAMIC-BOUNDARY:, or T.untyped — <reason>).'
        MSG_UNSAFE = 'T.unsafe requires RATIONALE naming a metaprogramming pattern, or argument must be self.'

        EXCLUDED_PATHS = %w[/adapters/ /controllers/ /consumers/ lib/rubocop/ test/ spec/].freeze

        JUSTIFICATION_PATTERNS = %w[RATIONALE:].freeze

          # RATIONALE: DYNAMIC-BOUNDARY is a module-level exemption for
          # vendor-JSON adapter clusters where every method returns T.untyped
          # against the same dynamic boundary (e.g. a vendor API client).
          # Repeating the full RATIONALE per-sig was redundant boilerplate; the
          # module-level notice replaces it. Would need the dynamic boundary
          # to close (typed schema lands) to reconsider; the notice itself
          # carries the overturning condition.
        DYNAMIC_BOUNDARY_PATTERN = 'DYNAMIC-BOUNDARY:'

          # RATIONALE: scope/concern and message-bus DSL contexts are Rails
          # DSL contexts, not metaprogramming — admitting them let T.unsafe
          # calls pass with an unrelated RATIONALE. Would need a genuine
          # dynamic-dispatch pattern to reconsider; "metaprogramming" remains
          # the generic escape word.
        METAPROGRAMMING_KEYWORDS = %w[define_method method_missing send __send__ define_singleton_method metaprogramming].freeze

        def_node_matcher :t_untyped_call?, <<~PATTERN
          (send (const nil? :T) :untyped)
        PATTERN

        def_node_matcher :t_unsafe_call?, <<~PATTERN
          (send (const nil? :T) :unsafe ...)
        PATTERN

        def_node_matcher :t_unsafe_self?, <<~PATTERN
          (send (const nil? :T) :unsafe (self))
        PATTERN

        def on_new_investigation
          super
          @file_path = processed_source.file_path.to_s
        end

        def on_send(node)
          if t_untyped_call?(node)
            return unless enforced_path?
            return if skip_file?
            return if justified?(node)

            add_offense(node.loc.selector, message: MSG_UNTYPED)
          elsif t_unsafe_call?(node)
            return unless enforced_path?
            return if skip_file?
            return if t_unsafe_self?(node)
            return if unsafe_justified?(node)

            add_offense(node.loc.selector, message: MSG_UNSAFE)
          end
        end

        private

        def enforced_path?
          @file_path.include?('app/') || @file_path.include?('lib/')
        end

        def skip_file?
          EXCLUDED_PATHS.any? { |pattern| @file_path.include?(pattern) }
        end

        def justified?(node)
          preceding_comments(node).any? do |comment|
            text = comment.text
            JUSTIFICATION_PATTERNS.any? { |pattern| text.include?(pattern) } ||
              text.match?(/T\.untyped\s*[—-]/)
          end || dynamic_boundary_notice?
        end

        # True when the file carries a module/class-level DYNAMIC-BOUNDARY:
        # notice. Such a notice justifies every T.untyped in the file because
        # the entire module documents the dynamic boundary in one place (the
        # collapse pattern — see base.rb in model_intelligence/collectors).
        def dynamic_boundary_notice?
          processed_source.comments.any? do |comment|
            comment.text.include?(DYNAMIC_BOUNDARY_PATTERN)
          end
        end

        def unsafe_justified?(node)
          preceding_comments(node).any? do |comment|
            text = comment.text
            next unless text.include?('RATIONALE:')

            METAPROGRAMMING_KEYWORDS.any? { |keyword| text.downcase.include?(keyword.downcase) }
          end
        end
      end
    end
  end
end
