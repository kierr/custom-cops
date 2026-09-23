# typed: strict
# frozen_string_literal: true

# Custom cops loaded by RuboCop's require mechanism don't have T in scope.
# Sorbet annotations are for static analysis only; runtime must avoid T.* calls.

module RuboCop
  module Cop
    module Lint
      # Detects `update` (not `update_columns` or `update_all`) inside methods
      # called from after_save, after_create, or after_update callbacks. Using
      # `update` in these callbacks creates infinite recursion: Rails re-triggers
      # the callback on each `update` call, which calls `update` again, ad
      # infinitum. Use `update_columns` to bypass callbacks, or restructure the
      # logic to avoid mutating the record inside the callback.
      #
      # The cop resolves callback methods within the file by collecting all
      # after_save/after_create/after_update symbol arguments, then scanning the
      # bodies of the corresponding method definitions for bare `.update(` calls.
      # It does NOT flag `update_columns`, `update_all`, or `update_column` --
      # those are the intended safe alternatives.
      #
      # @example
      #
      #   # bad -- infinite recursion: after_save calls update, which re-triggers after_save
      #   class Invoice < ApplicationRecord
      #     after_save :recalculate_total
      #
      #     def recalculate_total
      #       update(total: compute_total)
      #     end
      #   end
      #
      #   # good -- update_columns bypasses callbacks
      #   class Invoice < ApplicationRecord
      #     after_save :recalculate_total
      #
      #     def recalculate_total
      #       update_columns(total: compute_total)
      #     end
      #   end
      #
      class UpdateInAfterCallback < Base
        MSG = 'Use `update_columns` instead of `update` in `%<method>s` -- `update` re-triggers after_* callbacks, causing infinite recursion.'

        # Callback macros that trigger the recursion risk.
        CALLBACK_MACROS = %i[after_save after_create after_update].freeze

        def on_new_investigation
          return unless processed_source.ast

          callback_methods = collect_callback_method_names
          return if callback_methods.empty?

          method_nodes = collect_method_nodes(callback_methods)

          callback_methods.each do |method_name|
            def_node = method_nodes[method_name]
            next unless def_node
            next unless def_node.body

            find_unsafe_updates(def_node.body, method_name.to_s)
          end
        end

        private

        # Walk the AST to find all after_save/after_create/after_update calls
        # and extract their symbol/string argument (the callback method name).
        def collect_callback_method_names
          names = Set.new

          processed_source.ast.each_node(:send) do |send_node|
            next unless CALLBACK_MACROS.include?(send_node.method_name)
            next unless send_node.receiver.nil?

            first_arg = send_node.arguments.first
            next unless first_arg

            case first_arg.type
            when :sym
              names.add(first_arg.value)
            when :str
              names.add(first_arg.value.to_sym)
            end
          end

          names
        end

        # Find def nodes matching the callback method names.
        def collect_method_nodes(callback_methods)
          nodes = {}

          processed_source.ast.each_node(:def) do |def_node|
            method_name = def_node.method_name
            next unless callback_methods.include?(method_name)
            next if nodes.key?(method_name)

            nodes[method_name] = def_node
          end

          nodes
        end

        # Walk the body of a callback method and flag any `.update` calls.
        # update_columns, update_column, and update_all are distinct method names
        # from :update, so checking == :update alone is sufficient.
        #
        # Any `.update` receiver is flagged, not only `self.update`: a class-level
        # re-save of the same record (`self.class.update(id: id, ...)`) also
        # re-triggers after_save/after_update on this record, so narrowing to
        # self-receivers would miss that recursion vector.
        #
        # NOTE: callback methods are resolved within the current file only; a
        # callback defined in a concern or included module is not scanned, so
        # the cop can false-negative when the handler lives elsewhere.
        def find_unsafe_updates(body_node, method_name)
          body_node.each_node(:send) do |send_node|
            next unless send_node.method_name == :update

            add_offense(send_node.loc.selector, message: format(MSG, method: method_name))
          end
        end
      end
    end
  end
end
