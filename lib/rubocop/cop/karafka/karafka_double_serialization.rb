# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Karafka
      # Detects `.to_json` on the `payload:` argument of Karafka produce calls when
      # `Karafka::Middleware::JsonSerializer` is configured as producer middleware.
      #
      # The middleware auto-serializes Hash/Array payloads to JSON. Manual `.to_json`
      # produces double-encoded JSON strings — downstream consumers receive raw strings
      # instead of parsed objects. This was a systemic bug affecting 16 files with 2 sites
      # still unfixed.
      #
      # The cop is gated on the presence of `Karafka::Middleware::JsonSerializer` in
      # `karafka.rb` or `config/karafka/`. Without the middleware registered, manual
      # `.to_json` is correct and the cop does not flag.
      #
      # @example
      #
      #   # bad — middleware auto-serializes, .to_json double-encodes
      #   produce_async(topic: 'events', payload: data.to_json)
      #   produce_sync(topic: 'events', payload: task.to_json, key: key)
      #   MyProducer.produce_async(topic: topic, payload: payload.to_json)
      #
      #   # good — pass Hash/Array directly, middleware handles serialization
      #   produce_async(topic: 'events', payload: data)
      #   produce_sync(topic: 'events', payload: task, key: key)
      #
      #   # good — String literals are already serialized, no double-encoding
      #   produce_async(topic: 'events', payload: '{"key":"value"}')
      #
      #   # good — non-payload keyword args are not affected
      #   produce_async(topic: 'events', payload: data, headers: meta.to_json)
      class KarafkaDoubleSerialization < Base
        MSG = 'Remove `.to_json` from payload — Karafka::Middleware::JsonSerializer auto-serializes Hash/Array payloads. Manual `.to_json` produces double-encoded JSON.'

        # Produce methods that flow through the WaterDrop middleware stack.
        PRODUCE_METHODS = %i[produce_sync produce_async produce].freeze

        # Matches any send node whose method is one of the produce methods.
        # NodePattern requires method-name alternation wrapped in `{}` set syntax.
        def_node_matcher :produce_call?, <<~PATTERN
          (send _ {#{PRODUCE_METHODS.map(&:inspect).join(' ')}} ...)
        PATTERN

        # Matches a keyword pair `payload: <value>.to_json` where the value is not
        # already a string literal. NodePattern matches `(pair (sym :payload) (send _ :to_json))`.
        def_node_matcher :payload_with_to_json?, <<~PATTERN
          (pair (sym :payload) $(send _ :to_json))
        PATTERN

        def on_send(node)
          return unless produce_call?(node)

          # Iterate keyword arguments (always the last argument when present).
          # Produce calls use kwargs: produce_async(topic: t, payload: p, key: k)
          kwargs = node.arguments.last
          return unless kwargs&.hash_type?

          kwargs.children.each do |pair|
            next unless pair.pair_type?

            to_json_send = payload_with_to_json?(pair)
            next unless to_json_send

            # The captured node is the `(send receiver :to_json)` call itself.
            # Check the receiver — if it is a string literal, .to_json is idempotent.
            next if string_literal?(to_json_send.receiver)

            add_offense(to_json_send.loc.selector, message: MSG)
          end
        end

        private

        # The receiver of `.to_json` is a string literal when the expression is
        # `"some string".to_json`. That is not double-encoding — it is idempotent.
        def string_literal?(node)
          node.str_type? || node.dstr_type?
        end
      end
    end
  end
end
