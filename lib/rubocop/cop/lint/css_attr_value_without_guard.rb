# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects Nokogiri/Nokolexbor `.attr('name').value` and
      # `.attribute('name').value` chains without nil guards, as well as
      # `css('selector').attr('name')` patterns where the intermediate result
      # can be nil.
      #
      # Nokogiri's `Node#attribute()` returns `nil` when the attribute is absent,
      # so `.value` on that nil raises `NoMethodError`. The same crash path exists
      # for `.attr().value` since Nokogiri's `Node#attr(name)` delegates to
      # `attribute(name).value` for a single argument.
      #
      # For Nokolexbor, `Node#attr(name)` returns `String | nil` directly.
      # Chaining `css('selector').attr('name')` without a nil guard crashes
      # when the CSS selector matches nothing (empty NodeSet) or the attribute
      # is absent.
      #
      # This cop extends `NokogiriAttrValueNilChain` coverage to include the
      # `.attr()` method and `css().attr()` chains.
      #
      # @example
      #
      #   # bad — .attr() returns nil for absent attributes; .value on nil crashes
      #   node.attr('href').value
      #
      #   # bad — css() can return empty NodeSet; .attr() on it returns nil
      #   doc.css('.card').attr('data-id')
      #
      #   # bad — .attribute() variant, same nil chain
      #   node.attribute('href').value
      #
      #   # good — safe navigation on .value
      #   node.attr('href')&.value
      #
      #   # good — safe navigation on .attr()
      #   doc.css('.card')&.attr('data-id')
      #
      #   # good — at_css returns nil directly, developer expectation differs
      #   doc.at_css('.card').attr('data-id')
      #
      #   # good — bracket access returns nil safely
      #   node['href']
      #
      class CssAttrValueWithoutGuard < Base
        MSG_ATTR_VALUE =
          'Use `&.value` or bracket access `node[%<arg>s]` — `%<method>s` returns nil ' \
          'when the attribute is absent, and `.value` on nil raises NoMethodError.'

        MSG_CSS_ATTR =
          'Use a nil guard or safe navigation after `.css(...).%<method>s` — ' \
          'an empty NodeSet makes `.attr()` return nil, causing NoMethodError on chained calls.'

        # Methods that retrieve attributes on Nokogiri/Nokolexbor nodes.
        ATTR_METHODS = %i[attr attribute].freeze

        # Matches `.attr('x').value` or `.attribute('x').value` without safe navigation
        # on the outer `.value` call. The outer :value must be a regular send (not csend).
        # The inner call can be send or csend — `node&.attr('foo').value` is still unsafe
        # because attr returns nil for absent attributes regardless of whether the receiver
        # was nil-safe.
        def_node_matcher :unsafe_attr_value_chain?, <<~PATTERN
          (send {(send $_ {:attr :attribute} ...) (csend $_ {:attr :attribute} ...)} :value)
        PATTERN

        # Matches `.css(...).attr('x')` or `.css(...).attribute('x')` without safe
        # navigation on the .attr/.attribute call itself.
        def_node_matcher :css_attr_chain?, <<~PATTERN
          (send $(send _ :css ...) {:attr :attribute} ...)
        PATTERN

        # Matches `.css(...).attr('x')&.something` — safe-navigated, acceptable.
        def_node_matcher :safe_navigated_css_attr?, <<~PATTERN
          (csend $(send _ :css ...) {:attr :attribute} ...)
        PATTERN

        def on_send(node)
          detect_attr_value_chain(node)
          detect_css_attr_chain(node)
        end

        private

        def detect_attr_value_chain(node)
          captured = unsafe_attr_value_chain?(node)
          return unless captured

          # Require at least one argument to .attr()/.attribute() — zero-arg calls
          # like config.attribute.value are not Nokogiri Node lookups.
          inner_call = node.receiver
          return unless inner_call.arguments.any?

          return if constant_receiver?(captured)

          method_name = inner_call.method_name
          arg_source = extract_arg_source(inner_call)
          message = format(MSG_ATTR_VALUE, arg: arg_source, method: method_name)

          add_offense(node.loc.selector, message: message)
        end

        def detect_css_attr_chain(node)
          matched = css_attr_chain?(node)
          return unless matched

          # Exclude at_css — returns nil directly, developer intent differs.
          return if matched.method_name == :at_css

          # If the .attr()/.attribute() result is immediately safe-navigated
          # (e.g., doc.css('x').attr('href')&.to_s), the parent will be a csend.
          return if safe_navigation_parent?(node)

          method_name = node.method_name
          message = format(MSG_CSS_ATTR, method: method_name)

          add_offense(node.loc.selector, message: message)
        end

        def constant_receiver?(node)
          return true if node&.const_type?

          return false unless node&.send_type?

          root = find_root_receiver(node)
          root&.const_type? || false
        end

        def find_root_receiver(node)
          return node unless node&.send_type?

          receiver = node.receiver
          receiver ? find_root_receiver(receiver) : node
        end

        # The parent of `doc.css('x').attr('y')` is a csend when written as
        # `doc.css('x').attr('y')&.something` — safe navigation makes it guarded.
        def safe_navigation_parent?(node)
          parent = node.parent
          parent&.csend_type? && parent.receiver == node
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
