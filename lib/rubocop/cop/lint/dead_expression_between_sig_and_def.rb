# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects orphaned expressions between a `sig` block and the following `def`.
      # Anything that evaluates and discards between `sig`/`def` is dead code — it
      # runs at class-load time inside the method body scope but its return value is
      # never used. Common causes: leftover debugging calls, accidental paste, or
      # partial edits that left a dangling expression.
      #
      # Only flags nodes inside a `begin` block where a `sig` block (braces or do/end)
      # is immediately followed by one or more non-`def` children before the `def`.
      # Comments are not AST nodes and are ignored.
      #
      # @example
      #   # bad — dangling method call between sig and def
      #   sig { void }
      #   some optional
      #   def my_method
      #   end
      #
      #   # bad — constant reference between sig and def
      #   sig { returns(Integer) }
      #   SOME_CONST
      #   def compute
      #   end
      #
      #   # good — sig immediately followed by def
      #   sig { void }
      #   def my_method
      #   end
      #
      #   # good — comment between sig and def (not an AST node)
      #   sig { void }
      #   # This method does X
      #   def my_method
      #   end
      class DeadExpressionBetweenSigAndDef < Base
        MSG = 'Expression between `sig` and `def` is dead code — remove it or move it into the method body.'

        # Matches `sig { ... }` and `sig do ... end` — both are `block` nodes
        # whose method call receiver is `sig`.
        def_node_matcher :sig_block?, <<~PATTERN
          (block (send nil? :sig) ...)
        PATTERN

        # Nodes that a `sig` legitimately types. Besides `def`, Sorbet sigs apply
        # to attribute macros (attr_reader/attr_writer/attr_accessor) and T::Struct
        # fields (prop). RATIONALE: without this, the cop false-flags every typed
        # `sig ... attr_reader` pair as a dead expression between sig and def.
        # Visibility-wrapped defs (`private def x`, `private_class_method def self.x`)
        # are a single send wrapping the def — the sig types the inner def, so the
        # whole send is a valid target.
        def_node_matcher :sig_target?, <<~PATTERN
          {
            def
            defs
            (send nil? {:attr_reader :attr_writer :attr_accessor :prop :const :delegate :define_method} ...)
            (send nil? {:private :protected :public :private_class_method :public_class_method :module_function} {def defs})
          }
        PATTERN

        def on_begin(node)
          children = node.children
          return if children.length < 3 # need at least sig, something, target

          children.each_with_index do |child, idx|
            next unless sig_block?(child)

            # Flag every sibling between this sig and the next sig or sig target.
            # Stopping at the next sig prevents one sig's scan from consuming a
            # following typed-attr declaration's sig and reader.
            ((idx + 1)...children.length).each do |j|
              sibling = children[j]
              break if sig_block?(sibling) || sig_target?(sibling)
              # Assignments have side effects (define a constant/variable) and
              # are not discarded expressions, so skip them.
              next if side_effectful_assignment?(sibling)
              # A bare visibility switch (`private` / `protected` / `public`
              # with no args) changes default visibility for later defs — side
              # effectful, and `sig; private; def x` still binds the sig via
              # method_added, so it is not dead.
              next if bare_visibility_switch?(sibling)

              add_offense(sibling, message: MSG)
            end
          end
        end

        def side_effectful_assignment?(node)
          %i[casgn lvasgn ivasgn cvasgn gvasgn].include?(node.type)
        end

        def bare_visibility_switch?(node)
          node.send_type? &&
            node.receiver.nil? &&
            node.arguments.empty? &&
            %i[private protected public].include?(node.method_name)
        end
      end
    end
  end
end
