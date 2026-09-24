# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `Concurrent::FixedThreadPool` or `Thread.new` in code that may use
      # ActiveRecord without evidence of connection pool sizing awareness.
      #
      # The default ActiveRecord connection pool is 5 connections. Creating a thread
      # pool with more threads than available connections causes connection starvation
      # and timeout errors under load. A production fix removed
      # a `Concurrent::FixedThreadPool.new(Concurrent.processor_count * 8)` that
      # exhausted the AR pool.
      #
      # Flagged code is fine when the pool threads do not touch ActiveRecord (pure CPU
      # work, HTTP calls, etc.) or when the connection pool is explicitly sized to
      # accommodate the threads. Suppress with `# RATIONALE:` when either condition holds.
      #
      # @example
      #
      #   # bad — processor_count can exceed default 5 AR connections
      #   Concurrent::FixedThreadPool.new(Concurrent.processor_count)
      #
      #   # bad — 32 threads with no pool size evidence
      #   Concurrent::FixedThreadPool.new(32)
      #
      #   # good — bounded to AR-safe default
      #   Concurrent::FixedThreadPool.new(5)
      #
      #   # good — size derived from data, capped to reasonable default
      #   Concurrent::FixedThreadPool.new([items.size, 5].min)
      #
      #   # good — connection pool awareness documented nearby
      #   # Connection pool sized to match: pool: 20 in database.yml
      #   Concurrent::FixedThreadPool.new(Concurrent.processor_count * 4)
      #
      class ConcurrentPoolWithoutConnectionLimit < Base
        MSG = 'Thread pool creation without evidence of ActiveRecord connection pool sizing — threads may exceed the default 5 AR connections.'

        # Numeric threshold above which a literal pool size is flagged.
        # The default AR pool is 5; anything at or below 5 is within safe bounds.
        AR_DEFAULT_POOL_SIZE = 5

        # Phrases that indicate ActiveRecord connection pool sizing awareness.
        # Multi-word phrases must use the array literal form (not %w) so that
        # "connection pool" is a single entry, not two separate keywords.
        POOL_AWARENESS_PHRASES = ['connection_pool', 'connection pool', 'ar pool', 'database.yml', 'pool:',
                                  'pool='].freeze

        POOL_METHOD_INDICATORS = %i[with_connection connection_pool].freeze

        def on_send(node)
          is_pool = concurrent_fixed_thread_pool_new?(node)
          is_thread = thread_new?(node)
          return unless is_pool || is_thread

          return if connection_pool_awareness?(node)
          # FixedThreadPool with a small literal or bounded argument is safe.
          return if is_pool && safe_pool_size?(node)

          add_offense(node)
        end

        private

        def concurrent_fixed_thread_pool_new?(node)
          return false unless node.method_name == :new

          receiver = node.receiver
          return false unless receiver&.const_type?

          receiver.source == 'Concurrent::FixedThreadPool'
        end

        def thread_new?(node)
          return false unless node.method_name == :new

          receiver = node.receiver
          return false unless receiver&.const_type?

          receiver.source == 'Thread'
        end

        # Returns true when the first argument to FixedThreadPool.new is provably
        # within AR-safe bounds: a small integer literal, a constant reference, or
        # a bounded expression using .min.
        def safe_pool_size?(node)
          arg = node.first_argument
          return false unless arg

          return true if small_literal?(arg)
          return true if bounded_expression?(arg)
          return true if constant_reference?(arg)

          false
        end

        def small_literal?(node)
          return false unless node.int_type?

          node.value <= AR_DEFAULT_POOL_SIZE
        end

        # Detects patterns like `[items.size, 5].min` or `[count, MAX].min`
        def bounded_expression?(node)
          return false unless node.send_type? && node.method_name == :min

          receiver = node.receiver
          return false unless receiver&.array_type?

          # Array contains at least one small literal or constant — bounded.
          receiver.children.any? { |child| small_literal?(child) || constant_reference?(child) }
        end

        # A bare constant name (e.g., MAX_THREADS, AR_DEFAULT_POOL_SIZE) is assumed
        # safe — the developer chose a named constant, implying intentional sizing.
        def constant_reference?(node)
          node.const_type?
        end

        def connection_pool_awareness?(node)
          preceding_comments_mention_pool?(node) || method_body_mentions_pool?(node)
        end

        def preceding_comments_mention_pool?(node)
          target_line = node.loc.line

          processed_source.comments.any? do |comment|
            next false if comment.loc.line >= target_line

            text = comment.text.downcase
            POOL_AWARENESS_PHRASES.any? { |phrase| text.include?(phrase) }
          end
        end

        def method_body_mentions_pool?(node)
          ancestor = node.each_ancestor(:def, :defs, :block).first
          return false unless ancestor

          ancestor.each_descendant(:send).any? do |send_node|
            POOL_METHOD_INDICATORS.include?(send_node.method_name)
          end
        end
      end
    end
  end
end
