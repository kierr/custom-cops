# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `check_*` method calls where the return value is discarded.
      # Methods starting with `check_` conventionally return a decision or
      # eligibility result. Discarding the result allows code to proceed as
      # if the check passed. Only flags `check_` prefix — `validate_*` and
      # `verify_*` typically raise on failure, making discard safe.
      #
      # @example
      #
      #   # bad — check result is discarded, code continues as if approved
      #   check_eligibility_and_track(intent, decision) if decision.approved?
      #
      #   # good
      #   if decision.approved?
      #     eligibility_decision = check_eligibility_and_track(intent, decision)
      #     return eligibility_decision if eligibility_decision
      #   end
      class DiscardedMethodResult < Base
        MSG = '`%<method_name>s` result is discarded. `check_` methods return decisions — capture the result.'

        def on_send(node)
          return unless node.method_name.to_s.start_with?('check_')
          return if return_value_used?(node)

          add_offense(node.loc.selector, message: format(MSG, method_name: node.method_name))
        end

        private

        def return_value_used?(node)
          parent = node.parent
          return false unless parent

          case parent.type
          when :lvasgn, :ivasgn, :cvasgn, :gvasgn,
               :return, :array, :hash, :pair, :and, :or
            true
          when :send
            parent.arguments.include?(node)
          when :if
            # Used in condition or as only expression in a branch
            # IfNode has no singular `branch` method; use `branches` (plural).
            parent.condition == node || parent.branches.empty?
          else
            false
          end
        end
      end
    end
  end
end
