# typed: false # RuboCop cop — T is undefined at load time
# frozen_string_literal: true

module RuboCop
  module Cop
    module Security
      # Detects `send(variable)` or `public_send(variable)` where the method name
      # argument comes from a variable rather than a literal symbol/string. Dynamic
      # dispatch with user-controlled or externally-derived method names enables
      # arbitrary method invocation — a common injection vector.
      #
      # Safe patterns (not flagged):
      # - Literal symbols: `send(:method_name)`
      # - Literal strings: `send("method_name")`
      #
      # @example
      #
      #   # bad — method name from variable (injection risk)
      #   send(user_input)
      #   public_send(method_name)
      #   obj.send(dynamic_method)
      #
      #   # good — literal method name
      #   send(:method_name)
      #   public_send("fetch")
      class NoDynamicSendFromVariable < Base
        MSG = 'Avoid dynamic `send`/`public_send` with a variable method name. Use a literal symbol/string or validate against an allowlist.'

        DYNAMIC_DISPATCH = %i[send public_send __send__].freeze

        def on_send(node)
          return unless DYNAMIC_DISPATCH.include?(node.method_name)

          first_arg = node.first_argument
          return unless first_arg

          # Allow literal symbols and strings — these are safe
          return if first_arg.sym_type? || first_arg.str_type?

          # Flag variables (lvar, ivar, csend, gvar) and other non-literal expressions
          add_offense(first_arg)
        end
      end
    end
  end
end
