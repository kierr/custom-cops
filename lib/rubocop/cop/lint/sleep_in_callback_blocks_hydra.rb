# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `sleep` inside Typhoeus on_complete/on_success/on_failure callback
      # blocks. `sleep` in these callbacks blocks the hydra event loop thread,
      # serializing all concurrent requests during the sleep period.
      #
      # Typhoeus::Hydra runs requests concurrently on a single thread via
      # libcurl's multi interface. Callbacks execute on that same thread.
      # A `sleep` inside a callback stalls the entire event loop, bypassing
      # the concurrency model and delaying every queued request.
      #
      # @example
      #
      #   # bad — blocks the hydra event loop
      #   request.on_complete do |response|
      #     sleep RETRY_DELAY
      #     process(response)
      #   end
      #
      #   # bad — lambda/proc callback with sleep
      #   on_complete: ->(response) { sleep 2; retry_search(response) }
      #
      #   # good — schedule retry without blocking
      #   request.on_complete do |response|
      #     schedule_retry(response, delay: RETRY_DELAY)
      #   end
      #
      #   # good — sleep outside any callback block
      #   sleep INITIAL_DELAY
      #   batch.run
      class SleepInCallbackBlocksHydra < Base
        MSG = 'Avoid `sleep` inside Typhoeus callback — it blocks the hydra event loop, serializing all concurrent requests.'

        # Typhoeus request callback methods that run on the hydra thread.
        CALLBACK_METHODS = %i[on_complete on_success on_failure].freeze

        # Kernel.sleep or bare sleep with any argument pattern.
        def_node_matcher :sleep_call?, <<~PATTERN
          (send {(const nil? :Kernel) nil?} :sleep ...)
        PATTERN

        # request.on_complete { |response| ... } — block form on a receiver.
        def_node_matcher :callback_block_on_receiver?, <<~PATTERN
          (block (send _ {:on_complete :on_success :on_failure}) ...)
        PATTERN

        # on_complete: proc { ... } or on_complete: -> { ... } — keyword arg form.
        def_node_matcher :callback_proc_in_kwargs?, <<~PATTERN
          ({block numblock} (send _ {:proc :lambda}) ...)
        PATTERN

        def on_send(node)
          return unless sleep_call?(node)
          return unless inside_callback?(node)

          add_offense(node.loc.selector)
        end

        private

        # Walk ancestors to determine if this sleep is inside a Typhoeus callback.
        # Matches both receiver-block form (`request.on_complete { ... }`) and
        # keyword-argument proc/lambda form (`on_complete: proc { ... }`).
        def inside_callback?(node)
          node.each_ancestor.any? do |ancestor|
            callback_block_on_receiver?(ancestor)
          end || proc_in_callback_kwargs?(node)
        end

        # Checks whether a proc/lambda block (used as on_complete: -> { ... })
        # is passed as a keyword argument named on_complete/on_success/on_failure.
        #
        # AST structure: send > hash > pair(sym :on_complete, block(send :proc))
        # The block's parent is the pair, not the send.
        def proc_in_callback_kwargs?(node)
          node.each_ancestor(:block, :numblock).any? do |block_node|
            next unless callback_proc_in_kwargs?(block_node)

            pair_node = block_node.parent
            next unless pair_node&.pair_type?

            key = pair_node.children[0]
            key.sym_type? && CALLBACK_METHODS.include?(key.value)
          end
        end
      end
    end
  end
end
