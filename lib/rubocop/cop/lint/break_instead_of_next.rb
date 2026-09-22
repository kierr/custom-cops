# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `break` inside iterator blocks where `next` was likely intended.
      # Flags when `break` follows a positive existence/presence check inside
      # an accumulating iterator — the intent is to skip the current iteration,
      # not terminate the entire loop.
      #
      # @example
      #
      #   # bad — terminates entire loop on first match
      #   results.each do |batch|
      #     non_existing = find_missing(batch)
      #     break if non_existing.present?
      #   end
      #
      #   # good — skips to next iteration
      #   results.each do |batch|
      #     non_existing = find_missing(batch)
      #     next if non_existing.present?
      #   end
      class BreakInsteadOfNext < Base
        extend AutoCorrector

        MSG = 'Use `next` instead of `break` in accumulating iterator — `break` terminates the entire loop.'

        PRESENCE_METHODS = %i[present? any? exist? exists?].freeze

        def on_break(node)
          return unless inside_accumulating_iterator?(node)

          condition = presence_condition_for(node)
          return unless condition
          return unless presence_check?(condition) || negated_absence_check?(condition)

          add_offense(node) do |corrector|
            corrector.replace(node.loc.keyword, 'next')
          end
        end

        private

        def inside_accumulating_iterator?(node)
          block = node.each_ancestor(:block).first
          return false unless block

          method_name = block.send_node.method_name
          %i[each map collect flat_map select reject filter].include?(method_name)
        end

        # `break if cond` (modifier form) parses as (if cond (break) nil),
        # so the condition lives on the break's parent if-node, not on a child.
        # `break unless cond` parses as (if cond nil (break)).
        def presence_condition_for(break_node)
          parent = break_node.parent
          return nil unless parent&.if_type?

          # Only match the guard shape: the if-node has the break as its sole
          # non-nil branch (modifier/unless-guard form). An if/else block with
          # a break in one branch is not a guard and is out of scope.
          true_branch, false_branch = parent.branches
          if true_branch == break_node && false_branch.nil?
            parent.condition
          elsif false_branch == break_node && true_branch.nil?
            # `break unless cond` — the break fires when the condition is false,
            # so the effective checked condition is the negation. presence_check?
            # does not apply here; only negated_absence_check? is meaningful, and
            # it already inspects the condition node for a `!blank?` shape that is
            # independent of the unless polarity.
            parent.condition
          end
        end

        def presence_check?(node)
          return false unless node&.send_type?

          PRESENCE_METHODS.include?(node.method_name)
        end

        def negated_absence_check?(node)
          return false unless node&.send_type?

          return false unless node.method_name == :!

          receiver = node.receiver
          return false unless receiver&.send_type?

          %i[blank? empty? nil?].include?(receiver.method_name)
        end
      end
    end
  end
end
