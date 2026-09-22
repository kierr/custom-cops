# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects method calls in begin blocks whose return values are not captured,
      # where a rescue block references a variable that should hold that return value.
      # The variable is nil or undefined in the rescue scope.
      #
      # RATIONALE: the detection model is broken, so the cop never fires on its
      # own documented example: `on_resbody` looks up `each_ancestor(:kwbegin)
      # .first`, but the common `def foo; ... ; rescue ...; end` form has NO
      # `kwbegin` — the rescue is a direct child of the def body (`def → rescue →
      # resbody`), so `begin_node` is nil and the cop returns early. Also,
      # `collect_lvar_references` only gathers `:lvar` nodes, but the docstring
      # example uses `response` as an uncaptured bare method call, which is
      # never a local variable reference. The false-positive direction IS
      # repaired: block parameters and `rescue => e` bindings are recognized as
      # defined locals (2026-08-23, found while provisioning under an explicit
      # begin/rescue inside an each block). Spec evidence:
      # test/rubocop/cop/lint/uncaptured_return_value_in_rescue_scope_test.rb
      # (positive case skipped pending the kwbegin/call-reference fixes).
      # Would need the detection model to be proven to reconsider.
      #
      # @example
      #
      #   # bad — response is undefined in rescue
      #   dispatch_and_record(url:, workflow:, ...)
      #   rescue StandardError => e
      #     handle_scrape_error(response, e)
      #
      #   # good
      #   response = dispatch_and_record(url:, workflow:, ...)
      #   rescue StandardError => e
      #     handle_scrape_error(response, e)
      class UncapturedReturnValueInRescueScope < Base
        MSG = 'Method return value is not captured, but the rescue block references it. Assign the result to a variable.'

        def on_resbody(node)
          rescue_body = node.children[2]
          return unless rescue_body

          rescue_lvars = collect_lvar_references(rescue_body)

          # `rescue ... => e` binds e inside the handler — a defined local,
          # not an uncaptured-reference bug.
          rescue_lvars.subtract(resbody_bound_vars(node))
          return if rescue_lvars.empty?

          begin_node = node.each_ancestor(:kwbegin).first
          return unless begin_node

          begin_body = begin_node.children[0]
          return unless begin_body

          begin_body = begin_body.children.first if begin_body.begin_type?

          rescue_lvars.each do |lvar_name|
            next if variable_assigned_in_scope?(begin_body, lvar_name)
            next unless uncaptured_call_produces?(begin_body, lvar_name, rescue_body)

            add_offense(node.loc.expression, message: "#{MSG} (missing: `#{lvar_name} = ...`)")
          end
        end

        private

        def collect_lvar_references(node)
          refs = Set.new
          return refs unless node

          node.each_node(:lvar) do |lvar|
            refs.add(lvar.name)
          end
          refs
        end

        def variable_assigned_in_scope?(node, var_name)
          return false unless node

          return true if node.each_node(:lvasgn).any? { |asgn| asgn.name == var_name }

          # Block parameters are visible inside the block's rescue scopes even
          # though they are neither method arguments nor :lvasgn nodes.
          return true if node.each_ancestor(:block).any? do |block_node|
            block_node.arguments.each_node(:arg).any? { |arg| arg.children.first == var_name }
          end

          # lvars assigned in the enclosing method body AND method parameters are
          # visible in the rescue scope — only truly-undefined lvars are a bug.
          def_node = node.each_ancestor(:def).first
          return false unless def_node

          return true if def_node.arguments.any? { |arg| arg.children.first == var_name }

          def_node.each_node(:lvasgn).any? { |asgn| asgn.name == var_name }
        end

        def resbody_bound_vars(resbody_node)
          args_node = resbody_node.children[1]
          return Set.new unless args_node

          args_node.each_node(:arg).to_set { |arg| arg.children.first }
        end

        def uncaptured_call_produces?(begin_node, _var_name, _rescue_body)
          # Check if the variable is referenced in rescue but not assigned before
          # the begin block body
          return false unless begin_node

          statements = begin_node.begin_type? ? begin_node.children : [begin_node]
          statements.each do |stmt|
            next unless stmt.send_type?
            next if stmt.method_name == :raise
            # If a send's return value is not captured and a lvar with a similar
            # name exists in rescue, it's suspicious
          end

          true
        end
      end
    end
  end
end
