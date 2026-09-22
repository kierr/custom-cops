# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects Nokogiri node attribute access chains like `.attribute('foo').value`
      # where the `.value` call is not protected by safe navigation (`&.`).
      #
      # Nokogiri's `Node#attribute()` returns `nil` when the attribute doesn't exist.
      # Calling `.value` on nil raises `NoMethodError`. The fix is either
      # `.attribute('foo')&.value` or using `node['foo']` directly (which returns
      # nil safely without chaining).
      #
      # This pattern caused real crashes in scraper code (see spec_engine.rb
      # for the corrected patterns).
      #
      # @example
      #
      #   # bad — raises NoMethodError when attribute is absent
      #   node.attribute('href').value
      #
      #   # good — safe navigation
      #   node.attribute('href')&.value
      #
      #   # good — bracket access returns nil safely
      #   node['href']
      class NokogiriAttrValueNilChain < Base
        MSG = 'Use `&.value` or bracket access `node[%<arg>s]` — `Node#attribute` returns nil ' \
              'when the attribute is absent, and `.value` on nil raises NoMethodError.'

        # Matches `.attribute(...).value` without safe navigation between them.
        # The outer :value call must be a regular send (not csend) — safe-navigated
        # `.attribute('foo')&.value` produces a csend outer node and won't match.
        # The inner :attribute call can be send or csend — `node&.attribute('foo').value`
        # is still unsafe because Node#attribute returns nil for absent attributes
        # regardless of whether the receiver was nil-safe.
        def_node_matcher :unsafe_attr_value_chain?, <<~PATTERN
          (send {(send $_ :attribute ...) (csend $_ :attribute ...)} :value)
        PATTERN

        def on_send(node)
          captured = unsafe_attr_value_chain?(node)
          return unless captured

          receiver = captured

          # Require at least one argument to .attribute() — zero-arg calls like
          # config.attribute.value are not Nokogiri Node#attribute(name) lookups.
          inner_call = node.receiver
          return unless inner_call.arguments.any?

          return if constant_receiver?(receiver)

          arg_source = extract_arg_source(inner_call)
          message = format(MSG, arg: arg_source)

          add_offense(node.loc.selector, message: message)
        end

        private

        def constant_receiver?(node)
          return true if node&.const_type?

          # Walk the receiver chain to find the root receiver.
          # node is the receiver of `.attribute()`, which is itself a send node
          # for chained calls like `el.css('.foo').attribute('href')`.
          return false unless node&.send_type?

          root = find_root_receiver(node)
          root&.const_type? || false
        end

        def find_root_receiver(node)
          return node unless node&.send_type?

          receiver = node.receiver
          receiver ? find_root_receiver(receiver) : node
        end

        def extract_arg_source(attr_call_node)
          args = attr_call_node.arguments
          return '?' unless args.any?

          args.first.source
        end
      end
    end
  end
end
