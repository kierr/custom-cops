# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Sorbet
      # Detects `is_a?(T.untyped)` or `kind_of?(T.untyped)` calls.
      # `T.untyped` matches all values, so `x.is_a?(T.untyped)` is always true.
      # This is always a mistake — the developer likely meant to check for a specific type.
      #
      # @example
      #   # bad
      #   x.is_a?(T.untyped)
      #   x.kind_of?(T.untyped)
      #
      #   # good
      #   x.is_a?(String)
      #   x.kind_of?(Integer)
      class IsAUntypedAlwaysTrue < Base
        MSG = '`%<method>s(T.untyped)` is always true. T.untyped matches all values. Use a specific type or remove the check.'

        METHODS = %i[is_a? kind_of?].freeze

        def_node_matcher :is_a_untyped?, <<~PATTERN
          (send _ {:is_a? :kind_of?} (send (const nil? :T) :untyped))
        PATTERN

        def on_send(node)
          return unless is_a_untyped?(node)

          add_offense(node.loc.selector, message: format(MSG, method: node.method_name))
        end
      end
    end
  end
end
