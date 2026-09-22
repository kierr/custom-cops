# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # Detects `Hash#delete` on method parameters, which mutates the caller's hash.
      # Use `.dup.delete` or extract values before deletion to avoid side effects.
      #
      # RATIONALE: `*args` and `**opts` are excluded — Ruby packs splat/keyword-rest
      # into a fresh collection on each call, so mutating them cannot reach the caller.
      # Would need Ruby to forward the caller's original collection by reference to reconsider.
      #
      # @example
      #
      #   # bad — mutates caller's hash
      #   def initialize(args)
      #     @name = args.delete(:name)
      #   end
      #
      #   # good
      #   def initialize(args)
      #     @name = args.dup.delete(:name)
      #   end
      class HashDeleteWithoutDup < Base
        extend AutoCorrector

        MSG = 'Mutating method parameter via `delete`. Use `.dup.delete` or extract the value to avoid side effects on the caller.'

        def_node_matcher :param_delete?, <<~PATTERN
          (send (lvar _) :delete ...)
        PATTERN

        def on_send(node)
          return unless node.method_name == :delete
          return unless param_delete?(node)
          return unless parameter_name?(node.receiver)

          add_offense(node) do |corrector|
            corrector.insert_before(node.loc.expression, "#{node.receiver.source}.dup.")
          end
        end

        private

        def parameter_name?(node)
          return false unless node&.lvar_type?

          name = node.name
          def_node = node.each_ancestor(:def, :defs).first
          return false unless def_node

          def_node.arguments.any? do |arg|
            case arg.type
            when :arg, :optarg, :kwoptarg, :kwarg
              arg.children.first == name
            else
              false
            end
          end
        end
      end
    end
  end
end
