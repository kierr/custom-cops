# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Karafka
      # Detects `.to_json` on Hash/Array values assigned to local variables that later flow
      # into `payload:` keyword arguments of Karafka produce calls.
      #
      # `KarafkaDoubleSerialization` catches inline `.to_json` directly on the `payload:`
      # keyword (e.g., `produce_async(payload: x.to_json)`), but missed cases where
      # `.to_json` is called on an intermediate variable:
      #
      #   payload = response.value!.to_json
      #   produce_async(topic: topic, payload: payload)
      #
      # Karafka::Middleware::JsonSerializer auto-serializes Hash/Array payloads. Manual
      # `.to_json` produces double-encoded JSON strings. Git history shows 8+ fixes across
      # multiple services and consumers.
      #
      # @example
      #
      #   # bad — variable assigned from .to_json flows into payload:
      #   payload = response.value!.to_json
      #   produce_async(topic: 'events', payload: payload)
      #
      #   # bad — reassigned variable
      #   json = data.to_json
      #   produce_sync(topic: 'events', payload: json)
      #
      #   # good — pass the object directly, middleware handles serialization
      #   payload = response.value!
      #   produce_async(topic: 'events', payload: payload)
      #
      #   # good — inline without .to_json
      #   produce_async(topic: 'events', payload: data)
      #
      #   # good — variable not from .to_json
      #   payload = '{"already":"serialized"}'
      #   produce_async(topic: 'events', payload: payload)
      class PayloadToJsonBeforeProduce < Base
        MSG = 'Variable `%<name>s` was assigned from `.to_json` and flows into `payload:` — ' \
              'Karafka::Middleware::JsonSerializer auto-serializes. This produces double-encoded JSON.'

        # Produce methods that flow through the WaterDrop middleware stack.
        PRODUCE_METHODS = %i[produce_sync produce_async produce].freeze

        def_node_matcher :produce_call?, <<~PATTERN
          (send _ {#{PRODUCE_METHODS.map(&:inspect).join(' ')}} ...)
        PATTERN

        # Matches a keyword pair `payload: <lvar>` where the value is a local variable reference.
        def_node_matcher :payload_lvar?, <<~PATTERN
          (pair (sym :payload) (lvar $_))
        PATTERN

        def on_send(node)
          return unless produce_call?(node)

          kwargs = node.arguments.last
          return unless kwargs&.hash_type?

          kwargs.children.each do |pair|
            next unless pair.pair_type?

            lvar_name = payload_lvar?(pair)
            next unless lvar_name

            to_json_node = find_to_json_assignment(node, lvar_name)
            next unless to_json_node

            add_offense pair, message: format(MSG, name: lvar_name)
          end
        end

        private

        # Find the last assignment to `lvar_name` within the same method/block scope
        # that precedes the produce call. Only flags when the effective (last) assignment
        # uses `.to_json` — if the variable is later reassigned without `.to_json`, the
        # produce call receives the non-JSON value.
        def find_to_json_assignment(produce_node, lvar_name)
          method_node = enclosing_def_or_block(produce_node)
          return nil unless method_node

          # Collect all assignments to this lvar in document order.
          assignments = method_node.each_descendant(:lvasgn).select do |lvasgn|
            lvasgn.children.first == lvar_name
          end

          return nil if assignments.empty?

          # Use the last assignment — it determines the value at the produce call site.
          last_assignment = assignments.last
          rhs = last_assignment.children.last

          # Guard: a value-less lvasgn (e.g. the left-hand side of a destructuring
          # assignment like `envelope, headers = wrap(...)`) has only the lvar name
          # Symbol as children.last, so rhs is not an AST node and send_type? is undefined.
          return rhs if rhs.is_a?(RuboCop::AST::Node) && rhs.send_type? && rhs.method_name == :to_json

          nil
        end

        # Find the enclosing method definition or block that contains the produce call.
        # This scopes variable tracking to the same lexical boundary.
        def enclosing_def_or_block(node)
          node.each_ancestor(:def, :defs, :block).first
        end
      end
    end
  end
end
