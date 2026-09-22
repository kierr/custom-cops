# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Karafka
      # Bans direct reads of the global `Karafka.producer` in application code.
      # Produce calls should route through a facade class that applies a
      # `kafka_enabled?` off-switch, a `producer_available?` nil-guard,
      # and structured error handling. A direct getter read discards all
      # three guarantees at that call site.
      #
      # Infrastructure scoping is in the .rubocop.yml Exclude (the facade
      # itself, the karafka.rb producer bootstrap, shutdown flush, test/) —
      # the single governed source.
      #
      # The assignment form (`Karafka.producer = x`) is deliberately allowed:
      # binding or replacing the producer is infrastructure wiring, not message
      # production; only unguarded getter reads are confined.
      #
      # @example
      #   # bad — skips the disable flag, nil-guard, and structured error handling
      #   Karafka.producer.produce_many_async(messages)
      #
      #   # good — route through your project's producer facade
      #   MyProducerFacade.produce_many_async(messages)
      class NoGlobalProducerAccess < Base
        MSG = 'Direct Karafka.producer access bypasses the message facade. Produce through ' \
              'your project\'s producer facade class, which applies the kafka_enabled? off-switch, ' \
              'the producer_available? nil-guard, and structured error handling.'

        def_node_matcher :global_producer_getter?, <<~PATTERN
          (send (const {nil? (cbase)} :Karafka) :producer)
        PATTERN

        def on_send(node)
          return unless global_producer_getter?(node)

          add_offense(node)
        end
      end
    end
  end
end
