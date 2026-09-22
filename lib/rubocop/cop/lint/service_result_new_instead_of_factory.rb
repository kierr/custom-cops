# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `ServiceResult.new(success: ..., data: ..., message: ...)` and recommends
      # `ServiceResult.success` or `ServiceResult.failure` factory methods instead.
      #
      # The factory methods enforce consistent construction and prevent invalid states
      # like `success: true` with an `error:` parameter, or `success: false` without a
      # meaningful `message:`. The raw constructor bypasses the semantic checks that
      # the factory methods provide.
      #
      # Test files are excluded — test mocking may require raw construction for precise
      # control over the object state under test.
      #
      # @example
      #
      #   # bad — raw constructor bypasses factory checks
      #   ServiceResult.new(success: true, data: items, message: 'Fetched')
      #   ServiceResult.new(success: false, message: 'Not found', error: err)
      #
      #   # good — factory methods enforce semantic correctness
      #   ServiceResult.success(data: items, message: 'Fetched')
      #   ServiceResult.failure(message: 'Not found', error: err)
      #
      #   # good — test files are excluded (mocking may need raw construction)
      #   # In test files, ServiceResult.new is allowed without offense.
      class ServiceResultNewInsteadOfFactory < Base
        extend AutoCorrector

        MSG = 'Use `ServiceResult.success(...)` or `ServiceResult.failure(...)` instead of `ServiceResult.new`.'

        # Matches `ServiceResult.new(...)` with a hash argument containing `success:` key.
        def_node_matcher :service_result_new_with_success?, <<~PATTERN
          (send
            $(const _ :ServiceResult)
            :new
            {(hash <(pair (sym :success) _) ...>) (pair (sym :success) _) ...}
          )
        PATTERN

        def on_send(node)
          return unless node.method_name == :new

          const_node = service_result_new_with_success?(node)
          return unless const_node

          success_value = extract_success_value(node)
          return if success_value.nil?

          replacement = build_replacement(node, success_value)

          add_offense(node.loc.selector) do |corrector|
            corrector.replace(node.loc.expression, replacement)
          end
        end

        private

        # Extract the value of the `success:` keyword argument.
        # Returns `true`, `false`, or nil (if not determinable).
        def extract_success_value(node)
          hash_arg = find_hash_arg(node)
          return nil unless hash_arg

          success_pair = find_pair(hash_arg, :success)
          return nil unless success_pair

          value_node = success_pair.value
          return true if value_node.true_type?
          return false if value_node.false_type?

          nil
        end

        # Build the replacement source string for auto-correct.
        def build_replacement(node, success_value)
          hash_arg = find_hash_arg(node)
          kwargs = hash_arg ? extract_remaining_kwargs(hash_arg, success_value) : []

          method = success_value ? 'success' : 'failure'

          if kwargs.empty?
            "ServiceResult.#{method}"
          else
            "ServiceResult.#{method}(#{kwargs.join(', ')})"
          end
        end

        def find_hash_arg(node)
          node.arguments.find(&:hash_type?)
        end

        def find_pair(hash_node, key_name)
          hash_node.pairs.find do |pair|
            pair.key.sym_type? && pair.key.value == key_name
          end
        end

        # Extract all keyword arguments except `success:`, optionally filtering
        # args that are semantically inappropriate for the factory method.
        # `ServiceResult.success` should omit `error:` (success results do not carry errors).
        def extract_remaining_kwargs(hash_node, success_value)
          hash_node.pairs.each_with_object([]) do |pair, kwargs|
            key = pair.key
            next unless key.sym_type?

            key_name = key.value
            # Always skip `success:` — the factory method encodes it.
            next if key_name == :success

            # Success results should not carry an `error:` parameter.
            next if success_value && key_name == :error

            kwargs << pair.source
          end
        end
      end
    end
  end
end
