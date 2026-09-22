# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Security
      # Detects `constantize` and `safe_constantize` on values derived from
      # untrusted sources — method parameters, `params[]`, model attributes
      # (DB columns), or HTTP responses — without an explicit allowlist guard.
      #
      # `constantize` loads any class matching the string. An attacker who
      # controls the source value can instantiate arbitrary classes. The safe
      # pattern is to validate the value against a fixed set (Set, Array,
      # `include?`, `in?`) before calling constantize, or use a static
      # registry hash instead.
      #
      # String and symbol literals are safe — they cannot be influenced at
      # runtime. Namespace-prefix guards (e.g., `start_with?('Actions::')`)
      # and `respond_to?` interface checks are also accepted as mitigations.
      #
      # @example
      #
      #   # bad — receiver from method param, no allowlist
      #   def resolve(name)
      #     name.constantize
      #   end
      #
      #   # bad — receiver from DB column via model attribute
      #   record.service_name.constantize
      #
      #   # bad — receiver from params
      #   params[:type].constantize
      #
      #   # good — literal string
      #   "MyClass".constantize
      #
      #   # good — allowlist guard
      #   ALLOWED = %w[Actions::Foo Actions::Bar].freeze
      #   return unless ALLOWED.include?(service_name)
      #   service_name.constantize
      #
      #   # good — namespace prefix guard
      #   return unless service_name.start_with?('Actions::')
      #   service_name.constantize
      class ConstantizeFromUntrustedSource < Base
        MSG = 'Avoid `constantize`/`safe_constantize` on untrusted values without an allowlist guard. ' \
              'Use a static registry or validate against a fixed set.'

        CONSTANTIZE_METHODS = %i[constantize safe_constantize].freeze

        # Methods that read from external input or model state.
        UNTRUSTED_SOURCES = %i[params].freeze

        # Methods that serve as allowlist guards when they appear in a preceding
        # conditional in the same method body.
        ALLOWLIST_GUARD_METHODS = %i[include? member? cover?].freeze

        # Namespace-prefix and interface-check methods also qualify as guards.
        NAMESPACE_GUARD_METHODS = %i[start_with? end_with?].freeze
        INTERFACE_GUARD_METHODS = %i[respond_to?].freeze

        def on_send(node)
          return unless CONSTANTIZE_METHODS.include?(node.method_name)

          receiver = node.receiver
          return unless receiver

          return if literal_receiver?(receiver)
          return if allowlist_guard_present?(node)

          # Flag if receiver traces to an untrusted source.
          return unless untrusted_receiver?(receiver)

          add_offense(node.loc.selector)
        end

        private

        def literal_receiver?(node)
          node.str_type? || node.sym_type?
        end

        # Walk up the AST from the constantize call looking for a preceding
        # conditional that guards the receiver with an allowlist check.
        # Accepts: `include?`, `member?`, `cover?`, `start_with?`,
        # `end_with?`, `respond_to?`.
        def allowlist_guard_present?(constantize_node)
          method_node = find_enclosing_method_or_block(constantize_node)
          return false unless method_node

          guard_methods = ALLOWLIST_GUARD_METHODS + NAMESPACE_GUARD_METHODS + INTERFACE_GUARD_METHODS

          # Walk all send nodes in the method/block body and check for guard calls
          # that reference a value matching the constantize receiver.
          each_send_in(method_node).any? do |send_node|
            next unless guard_methods.include?(send_node.method_name)

            # The guard must reference the same value being constantized,
            # e.g., `ALLOWED.include?(service_name)` where `service_name.constantize`
            # is the call. We check if any argument to the guard matches the
            # source of the constantize receiver.
            guard_refs_same_value?(send_node, constantize_node.receiver)
          end
        end

        def guard_refs_same_value?(guard_send, constantize_receiver)
          # Pattern 1: guard argument matches constantize receiver.
          # e.g., `ALLOWED.include?(service_name)` where `service_name.constantize`
          guard_send.arguments.any? do |arg|
            receiver_matches?(arg, constantize_receiver)
          end ||
            # Pattern 2: guard receiver matches constantize receiver.
            # e.g., `service_name.start_with?('Actions::')` where `service_name.constantize`
            (guard_send.receiver && receiver_matches?(guard_send.receiver, constantize_receiver)) ||
            # Pattern 3: guard on the result of constantize (defensive check after load).
            # e.g., `klass.respond_to?(:call)` where `klass = service_name.constantize`
            guard_on_constantize_result?(guard_send, constantize_receiver)
        end

        # Check if the guard operates on a variable that was assigned from
        # `receiver.constantize` in the same method body.
        def guard_on_constantize_result?(guard_send, constantize_receiver)
          guard_recv = guard_send.receiver
          return false unless guard_recv&.lvar_type?

          method_node = find_enclosing_method_or_block(guard_send)
          return false unless method_node

          method_node.each_node(:lvasgn).any? do |asgn|
            next unless asgn.name == guard_recv.name

            rhs = asgn.to_a[1]
            next unless rhs&.send_type?
            next unless CONSTANTIZE_METHODS.include?(rhs.method_name)

            rhs_recv = rhs.receiver
            rhs_recv && receiver_matches?(rhs_recv, constantize_receiver)
          end
        end

        # Two AST nodes represent the same value if they are structurally
        # identical (same source representation). This handles local variables,
        # instance variables, send chains like `record.service_name`, etc.
        def receiver_matches?(guard_arg, constantize_receiver)
          guard_arg.source == constantize_receiver.source
        end

        def each_send_in(node, &block)
          return enum_for(:each_send_in, node) unless block

          node.each_node(:send).each(&block)
        end

        # Trace the receiver to determine if it originates from an untrusted
        # source: method parameters, params[], model attributes, or
        # local/instance variables assigned from those sources.
        def untrusted_receiver?(node)
          case node.type
          when :lvar
            name = node.name
            assigned_from_param?(node) || assigned_from_untrusted?(name, node)
          when :ivar
            # Instance variables set from external input (less common but possible).
            true
          when :send
            # Direct params[] access: `params[:type]`
            if UNTRUSTED_SOURCES.include?(node.method_name)
              true
            elsif node.method_name == :[]
              # Hash/array access on untrusted receiver: `params[:key]`
              untrusted_receiver?(node.receiver)
            else
              # Method chain on model or external response: `record.column`,
              # `response.body`, etc. Heuristic: any send chain that isn't a
              # known safe method (e.g., constantize itself) is potentially
              # untrusted if it reads from model state.
              model_attribute_access?(node)
            end
          else
            false
          end
        end

        def assigned_from_param?(lvar_node)
          method_node = find_enclosing_method_or_block(lvar_node)
          return false unless method_node

          method_name = lvar_node.name
          # Check if the method/block has a parameter with this name.
          params_node = method_node.arguments
          return false unless params_node

          params_node.children.any? do |param|
            case param.type
            when :arg, :optarg, :keyreq, :keyarg
              param.name == method_name
            else
              false
            end
          end
        end

        def assigned_from_untrusted?(lvar_name, original_node)
          method_node = find_enclosing_method_or_block(original_node)
          return false unless method_node

          # Find lvasgn nodes in the method body that assign to this variable.
          method_node.each_node(:lvasgn).any? do |asgn|
            next unless asgn.name == lvar_name

            rhs = asgn.to_a[1]
            next unless rhs

            untrusted_receiver?(rhs)
          end
        end

        def model_attribute_access?(node)
          # Heuristic: a send chain like `record.service_name` or
          # `action_type.service_name` where the receiver is a local variable
          # (likely a model instance). We cannot perfectly determine if the
          # receiver is a model, so we flag send chains where the base receiver
          # is an lvar and the chain has no constantize/safe_constantize in it.
          #
          # This catches `record.column.constantize` patterns where `record` is
          # a local variable (typically a model instance).
          base = deepest_receiver(node)
          base.lvar_type? || base.send_type?
        end

        def deepest_receiver(node)
          return node unless node.send_type?

          receiver = node.receiver
          return node unless receiver

          receiver.send_type? ? deepest_receiver(receiver) : receiver
        end

        def find_enclosing_method_or_block(node)
          node.each_ancestor(:def, :defs, :block).first
        end
      end
    end
  end
end
