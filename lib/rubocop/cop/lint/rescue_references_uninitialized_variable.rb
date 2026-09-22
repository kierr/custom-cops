# typed: false # RuboCop cop — T is undefined at load time
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `rescue => e` (or any exception variable binding) where the bound
      # variable is never referenced in the rescue body. An unused binding is dead
      # weight — if you don't need the exception object, use bare `rescue` or
      # omit the `=> e` entirely.
      #
      # The cop inspects the rescue body AST for any reference to the bound
      # variable name (lvar nodes matching the binding name). Logging calls,
      # re-raises, and Sentry captures are common legitimate uses.
      #
      # @example
      #
      #   # bad — `e` is never used
      #   begin
      #     risky_operation
      #   rescue StandardError => e
      #     nil
      #   end
      #
      #   # good — no binding needed
      #   begin
      #     risky_operation
      #   rescue StandardError
      #     nil
      #   end
      #
      #   # good — `e` is referenced
      #   begin
      #     risky_operation
      #   rescue StandardError => e
      #     logger.error('failed', error_message: e.message)
      #   end
      class RescueReferencesUninitializedVariable < Base
        MSG = 'Rescue variable `%<var>s` is not used in the rescue body. Remove the binding or use the variable.'

        def on_resbody(node)
          var_node = node.children[1]
          return unless var_node&.lvasgn_type?

          var_name = var_node.children[0]
          body = node.children[2]
          return unless body

          return if body_references_var?(body, var_name)

          add_offense(var_node, message: format(MSG, var: var_name))
        end

        private

        # Walk the body AST checking for any lvar reference to var_name.
        def body_references_var?(body, var_name)
          body.each_node(:lvar).any? { |lvar| lvar.children[0] == var_name }
        end
      end
    end
  end
end
