# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects arithmetic on method-call results in log keyword arguments where
      # the method name suggests it already accounts for the offset. Reports
      # actual+N instead of actual.
      #
      # @example
      #
      #   # bad — reprocessing_count already returns count+1
      #   logger.info('dlq.reprocessed', reprocessing_count: reprocessing_count(payload) + 1)
      #
      #   # good
      #   logger.info('dlq.reprocessed', reprocessing_count: reprocessing_count(payload))
      class RedundantArithmeticInLog < Base
        extend AutoCorrector

        MSG = 'Method name suggests it already accounts for the offset. Verify and remove the arithmetic.'

        # Matches method names whose final segment is a count-like word. The
        # leading `\b` is insufficient alone because `_` is a word char in Ruby
        # identifiers, so `total_count` has no boundary between `_` and `count`;
        # the docstring examples (`reprocessing_count`, `total_count`) would
        # never match. Anchoring to the end (or a trailing `?`) catches both
        # bare (`count`) and prefixed (`reprocessing_count`) forms without
        # matching unrelated words like `encounter` or `countess`.
        COUNT_METHODS = /(?:count|total|size|length|num|tally)\z/

        LOG_METHODS = %i[info warn error debug fatal].freeze

        def on_send(node)
          return unless LOG_METHODS.include?(node.method_name)
          return unless logger_receiver?(node)

          # Keyword arguments parse as a single `hash` child whose children are
          # the pairs — `each_child_node(:pair)` returns nothing because the
          # pairs are nested one level deeper. Walk into the hash node(s).
          pairs = node.each_child_node(:hash).flat_map { |h| h.each_child_node(:pair).to_a }
          pairs.each do |pair|
            value = pair.children[1]
            next unless arithmetic_on_count_method?(value)

            add_offense(value) do |corrector|
              method_call = value.children[0]
              corrector.replace(value, method_call.source)
            end
          end
        end

        private

        def logger_receiver?(node)
          receiver = node.receiver
          return true if receiver.nil? # implicit receiver

          return true if receiver.send_type? && receiver.method_name == :logger
          return true if receiver.ivar_type? && receiver.name == :@logger

          return true if receiver.lvar_type? && receiver.name == :logger
          return true if receiver.const_type?

          false
        end

        def arithmetic_on_count_method?(node)
          return false unless node&.send_type?
          return false unless %i[+ -].include?(node.method_name)

          lhs = node.children[0]
          rhs = node.children[2]
          return false unless lhs&.send_type?
          # RATIONALE: only a LITERAL offset on a count method is "redundant"
          # (e.g. `reprocessing_count + 1` where the method already returns
          # count+1). When the other operand is itself a count method or a
          # variable (e.g. `processed_ids.size - skipped_count`,
          # `run_ids.size - logged_ids.size`), the arithmetic computes a
          # DISTINCT metric and must not be stripped — a prior revision flagged
          # those and rubocop -a silently dropped the subtraction, corrupting
          # the metrics. Would need the cop to also catch `literal - count`
          # (currently only `count ± literal`) to broaden.
          return false unless rhs&.int_type?

          lhs.method_name.to_s.match?(COUNT_METHODS)
        end
      end
    end
  end
end
