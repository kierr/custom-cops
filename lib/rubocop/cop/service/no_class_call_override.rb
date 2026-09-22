# typed: strict
# frozen_string_literal: true

# All 27 errors are 7018 "call on T.untyped" from RuboCop AST API
# (Parser::AST::Node methods — no RBI coverage).
module RuboCop
  module Cop
    module Service
      class NoClassCallOverride < Base
        MSG = 'Concrete service classes should not override class-level `.call`; implement instance `#call` and inherit the class dispatcher.'

        # Both base classes share the same class-level dispatcher contract.
        # TypedService < ApplicationService; subclasses of either must not override
        # `self.call`. Without `TypedService` here, the policy for the canonical
        # base class relies on review alone.
        TRACKED_PARENTS = %w[ApplicationService TypedService].freeze

        def on_class(node)
          parent = node.parent_class
          return unless TRACKED_PARENTS.include?(parent&.const_name.to_s)

          each_top_level_child(node.body) do |child|
            next unless child.defs_type?
            next unless child.method_name == :call
            next unless child.defined_module_name.nil?

            add_offense(child.loc.name, message: MSG)
          end
        end

        private

        def each_top_level_child(body, &block)
          return unless body

          if body.begin_type?
            body.children.each(&block)
          else
            yield body
          end
        end
      end
    end
  end
end
