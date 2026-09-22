# typed: strict
# frozen_string_literal: true

# All 26 errors are 7018 "call on T.untyped" from RuboCop AST API
# (Parser::AST::Node methods — no RBI coverage).
module RuboCop
  module Cop
    module Karafka
      # Enforces that ApplicationConsumer subclasses override `process_messages`
      # instead of `consume`.
      #
      # ApplicationConsumer#consume is the single instrumentation wrapper
      # (tracing spans, metrics, structured logging, DLQ error handling).
      # Subclasses must not override it — they must implement #process_messages instead.
      #
      # @example
      #
      #   # bad — overrides the instrumentation wrapper
      #   class MyConsumer < ApplicationConsumer
      #     def consume
      #       process(messages)
      #     end
      #   end
      #
      #   # good — uses the template method hook
      #   class MyConsumer < ApplicationConsumer
      #     def process_messages
      #       process(messages)
      #     end
      #   end
      class RequireSuperInConsume < Base
        MSG = 'ApplicationConsumer#consume is the instrumentation wrapper. Override #process_messages instead of #consume.'

        SUPERCLASS_NAMES = %w[ApplicationConsumer Base].freeze

        def on_class(node)
          parent = node.parent_class
          return unless parent && SUPERCLASS_NAMES.include?(parent.const_name)

          consume_def = find_consume_def(node.body)
          return unless consume_def

          add_offense(consume_def.loc.name, message: MSG)
        end

        private

        def find_consume_def(body)
          return unless body

          if body.def_type? && body.method_name == :consume
            body
          elsif body.begin_type?
            body.children.find { |child| child.def_type? && child.method_name == :consume }
          end
        end
      end
    end
  end
end
