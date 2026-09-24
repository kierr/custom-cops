# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `rescue StandardError => e` blocks that bind the exception
      # variable but never reference it in any log call, raise, or tracking
      # call. The variable is bound but its error context is silently
      # discarded — either use the exception or remove the binding.
      #
      # Excludes cases where the rescue body re-raises bare (`raise` without
      # arguments), since the exception propagates regardless of whether the
      # bound variable is referenced.
      #
      # @example
      #
      #   # bad — e is bound but never used
      #   rescue StandardError => e
      #     logger.error('operation_failed')
      #     nil
      #
      #   # bad — e is bound, body does nothing with it
      #   rescue StandardError => e
      #     ServiceResult.failure(message: 'unknown error')
      #
      #   # good — e is referenced in a log call
      #   rescue StandardError => e
      #     logger.error('operation_failed', error_class: e.class.name, error_message: e.message)
      #
      #   # good — e is referenced via raise
      #   rescue StandardError => e
      #     raise CustomError, "wrapped: #{e.message}"
      #
      #   # good — bare raise re-raises the caught exception
      #   rescue StandardError => e
      #     logger.error('unexpected_failure')
      #     raise
      #
      #   # good — no variable binding at all (handled by RescueWithoutExceptionBinding)
      #   rescue StandardError
      #     nil
      class RescueWithoutErrorTracking < Base
        MSG = 'Exception variable `%<var>s` is bound but never referenced in the rescue body — use it or remove the binding.'

        def on_resbody(node)
          exception_var = exception_variable_name(node)
          return unless exception_var

          body = node.children[2]
          return unless body

          # Bare `raise` re-raises the caught exception; the variable is
          # propagating the error even though it is not textually referenced.
          return if body_has_bare_raise?(body)

          return if body_references_variable?(body, exception_var)

          add_offense(node.loc.keyword, message: format(MSG, var: exception_var))
        end

        private

        # ResbodyNode children: [0] exception types, [1] assignment, [2] body.
        # Assignment is an (lvasgn) node or nil for bare rescue.
        def exception_variable_name(node)
          assignment = node.children[1]
          return nil unless assignment

          assignment.name if assignment.lvasgn_type? || assignment.lvar_type?
        end

        # True when the body contains `raise` with no arguments (bare re-raise).
        def body_has_bare_raise?(body)
          body.each_node(:send).any? do |send_node|
            send_node.method_name == :raise && send_node.receiver.nil? && send_node.arguments.empty?
          end
        end

        # Walk all descendants for any lvar reference matching the exception
        # variable. This catches direct usage (`e`), method calls (`e.message`),
        # interpolation (`#{e}`), and keyword arg values (`error: e`).
        def body_references_variable?(body, var)
          body.each_descendant(:lvar).any? { |lvar_node| lvar_node.name == var }
        end
      end
    end
  end
end
