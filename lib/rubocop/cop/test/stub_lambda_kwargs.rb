# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Test
      # Flags `Minitest::stub` replacement lambdas that don't accept `**kwargs`.
      # `Minitest::stub` passes ALL kwargs to the replacement lambda, not just
      # what the caller provides. Stub lambdas must accept `**kwargs` to avoid
      # `ArgumentError` at runtime.
      #
      # @example
      #   # bad
      #   Minitest::stub(obj, :method, -> (arg) { result })
      #
      #   # good
      #   Minitest::stub(obj, :method, -> (arg, **) { result })
      #
      #   # good (already has **kwargs)
      #   Minitest::stub(obj, :method, -> (arg, **kwargs) { result })
      class StubLambdaKwargs < Base
        MSG = 'Minitest::stub replacement lambda must accept `**kwargs` (or `**`). `Minitest::stub` passes ALL kwargs to the stub.'

        # Matches Minitest::stub(obj, :method, -> (args) { body }) where the 5th
        # argument is a lambda literal. The AST represents `-> () {}` as a `block`
        # node wrapping `(send nil :lambda)`, not a `block_pass` (which is `&blk`).
        def_node_matcher :minitest_stub_with_lambda?, <<~PATTERN
          (send
            (const {nil? (cbase)} {:Minitest :MiniTest})
            :stub
            _
            _
            $block
          )
        PATTERN

        def on_send(node)
          lambda_node = minitest_stub_with_lambda?(node)
          return unless lambda_node

          arguments = lambda_node.arguments
          return if has_kwrest_arg?(arguments)

          add_offense(lambda_node.loc.expression, message: MSG)
        end

        private

        def has_kwrest_arg?(arguments)
          return false unless arguments

          arguments.children.any? { |arg| arg&.kwrestarg_type? }
        end
      end
    end
  end
end
