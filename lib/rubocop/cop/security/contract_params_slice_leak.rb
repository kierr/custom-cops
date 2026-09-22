# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Security
      # Detects `params.slice` in contract classes that passes raw
      # ActionController::Parameters string values through to consumers
      # instead of validated, coerced canonical values. Contracts should
      # build canonical hashes with coerced values.
      #
      # @example
      #
      #   # bad — passes raw string params through
      #   ValidationResult.new(params.slice(*DECLARED_KEYS), errors)
      #
      #   # good — builds canonical hash with coerced values
      #   canonical = {}
      #   validate_filter(params, canonical, errors)
      #   ValidationResult.new(canonical, errors)
      class ContractParamsSliceLeak < Base
        MSG = 'Avoid passing `params.slice` directly to results. Build a canonical hash with coerced values instead.'

        def_node_matcher :params_slice?, <<~PATTERN
          (send (send nil? :params) :slice ...)
        PATTERN

        def_node_matcher :params_slice_splat?, <<~PATTERN
          (send (send nil? :params) :slice (splat ...))
        PATTERN

        def on_send(node)
          return unless params_slice?(node) || params_slice_splat?(node)
          return unless in_contract_file?

          add_offense(node)
        end

        private

        def in_contract_file?
          processed_source.file_path.include?('/contracts/')
        end
      end
    end
  end
end
