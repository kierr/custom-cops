# typed: false # RuboCop cop — T is undefined at load time
# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module CustomCops
      # Shared by cops that accept a `RATIONALE:` exemption over a window of
      # comments above the offending node. Extracted from seven type-safety cops
      # that each copy-pasted the windowing + RATIONALE-prefix logic. One copy
      # had diverged to match a bare `RATIONALE` token (no colon), which the
      # canonical comment-prefix policy does not recognize as a valid
      # justification.
      #
      # Namespace-neutral: type-safety cops, security cops, and HTTP-namespace
      # cops all include it, so it lives at the `CustomCops` level rather than under
      # any single sub-namespace.
      #
      # RATIONALE: centralizing the matcher is what makes the canonical-prefix
      # rule hold across cops — a per-cop copy can drift back to the colon-less
      # form (as observed with three hand-rolled per-cop `rationale?`
      # matchers). Would need the canonical comment-prefix policy to admit
      # the colon-less `RATIONALE` token as a valid justification to
      # reconsider.
      #
      # NOTE: no `extend T::Helpers` / `requires_ancestor { Base }` — Sorbet's
      # T is undefined during RuboCop's require phase (see typed: false above);
      # include this module only in RuboCop::Cop::Base subclasses.
      module CommentWindow
        private

        # The contiguous comment block immediately above `node` — the node's
        # docstring. A multi-line RATIONALE in the docstring thus justifies a
        # `T.untyped` nested in the `sig` below it. When `node` sits inside a
        # `sig do ... end` block, the docstring lives above the `sig` keyword, so
        # the scan anchors on the sig block rather than the node's own line.
        #
        # The scan walks upward from the anchor, collecting consecutive comment
        # lines and stopping at the first blank or code line — the real bound.
        # `window` is only a far-back upper-bound cap (default 20), never a truncation
        # of a normal multi-line RATIONALE.
        def preceding_comments(node, window: 20)
          return [] unless node.loc.expression

          collect_contiguous_comments_above(comment_anchor_line(node), window: window)
        end

        # True when any comment in the contiguous block carries the canonical
        # `RATIONALE:` prefix. The colon is required by the canonical
        # comment-prefix policy; a bare `RATIONALE` is not a valid
        # justification.
        def rationale_comment?(node, window: 20)
          preceding_comments(node, window: window).any? do |comment|
            comment.text.include?('RATIONALE:')
          end
        end

        # Line whose docstring justifies the offending node. A node inside a
        # `sig { }` / `sig do ... end` block is justified by comments above the
        # `sig` keyword (the method docstring), not by comments adjacent to the
        # node's own deeper line inside the block.
        def comment_anchor_line(node)
          sig_block = enclosing_sig_block(node)
          sig_block ? sig_block.loc.expression.line : node.loc.expression.line
        end

        # Walk the parent chain to the nearest `sig` block wrapping `node`, if any.
        def enclosing_sig_block(node)
          current = node.parent
          while current
            return current if sig_block?(current)

            current = current.parent
          end
          nil
        end

        # `sig { }` and `sig do ... end` are RuboCop block nodes whose method is :sig.
        def sig_block?(node)
          node.block_type? && node.send_node.method_name == :sig
        end

        # Collect the unbroken run of comment lines directly above `line`,
        # scanning upward and stopping at the first blank or code line. Capped at
        # `window` against pathological comment headers. Returns source order.
        #
        # RATIONALE: walks `comments` in reverse line order rather than building
        # a line-keyed hash — `index_by` is ActiveSupport, which the RuboCop
        # process does not load (it never boots the app), so the scan stays
        # dependency-free core Ruby. Would need ActiveSupport core_ext loaded at
        # cop inspection time to reconsider.
        def collect_contiguous_comments_above(line, window:)
          expected = line - 1
          block = []
          processed_source.comments.reverse_each do |comment|
            comment_line = comment.loc.expression.line
            next if comment_line >= line
            break if comment_line != expected

            block << comment
            expected -= 1
            break if block.size >= window
          end
          block.reverse
        end
      end
    end
  end
end
