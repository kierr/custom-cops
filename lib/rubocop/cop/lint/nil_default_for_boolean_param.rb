# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects optional parameters with `nil` default where the corresponding
      # Sorbet sig declares the type as `T::Boolean`. `nil` is not a valid
      # `T::Boolean` value in Sorbet — the default should be `true` or `false`.
      #
      # @example
      #
      #   # bad — nil is not a valid T::Boolean
      #   sig { params(shell: T::Boolean).void }
      #   def run!(cmd, shell: nil)
      #
      #   # good
      #   sig { params(shell: T::Boolean).void }
      #   def run!(cmd, shell: false)
      class NilDefaultForBooleanParam < Base
        MSG = '`nil` default for parameter declared as `T::Boolean` in sig. Use `true` or `false`.'

        def_node_matcher :boolean_sig_param?, <<~PATTERN
          (pair (sym _) (const {nil? (cbase)} :Boolean))
        PATTERN

        def on_optarg(node)
          check_param(node)
        end

        # Keyword optional parameters (`shell: nil`) parse as `kwoptarg`, not
        # `optarg` (positional). The docstring examples all use keyword form, so
        # both handlers are required for the cop to fire on its intended targets.
        def on_kwoptarg(node)
          check_param(node)
        end

        def check_param(node)
          return unless node.children[1].nil_type?

          name = node.name
          return unless boolean_typed_in_sig?(name, node)

          add_offense(node.loc.expression)
        end

        private

        def boolean_typed_in_sig?(param_name, opt_node)
          def_node = opt_node.each_ancestor(:def, :defs).first
          return false unless def_node

          parent = def_node.parent
          return false unless parent&.begin_type?

          sig_node = find_preceding_sig(parent, def_node)
          return false unless sig_node

          sig_param_typed_boolean?(sig_node, param_name)
        end

        # Walk preceding siblings looking for a sig block immediately before the def.
        def find_preceding_sig(parent, def_node)
          siblings = parent.children
          idx = siblings.index(def_node)
          return nil unless idx&.positive?

          siblings[0...idx].reverse_each do |sib|
            return sib if sib.block_type? && sib.send_node&.method_name == :sig

            break
          end
          nil
        end

        # Find params call in sig body and check if param_name is typed as T::Boolean.
        def sig_param_typed_boolean?(sig_node, param_name)
          sig_node.each_node(:send).each do |send_node|
            next unless send_node.method_name == :params

            send_node.each_node(:pair).each do |pair|
              key_node = pair.children[0]
              next unless key_node.sym_type? && key_node.value == param_name

              return true if boolean_type?(pair.children[1])
            end
          end
          false
        end

        def boolean_type?(node)
          return false unless node

          case node.type
          when :const
            # T::Boolean or ::T::Boolean
            ['T::Boolean', '::T::Boolean'].include?(node.source)
          when :send
            # T::Boolean via send
            node.source == 'T::Boolean'
          else
            false
          end
        end
      end
    end
  end
end
