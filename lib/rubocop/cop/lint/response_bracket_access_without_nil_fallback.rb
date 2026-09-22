# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects single-level bracket hash access on response/result/data
      # variables where the returned value is iterated or chained without a nil
      # fallback. When the key is missing, `Hash#[]` returns nil; calling
      # `.each`, `.map`, `.filter_map`, or similar enumerable methods on nil
      # raises `NoMethodError`.
      #
      # The companion cop `ChainedHashAccessWithoutDig` covers two-plus-level
      # chains (`response['hits']['hits']`); this cop covers the single-level
      # case (`response['items']`) that ChainedHashAccessWithoutDig does not
      # flag.
      #
      # @example
      #
      #   # bad — nil.each raises NoMethodError when 'items' is missing
      #   response['items'].each { |item| process(item) }
      #   result['data'].map { |d| d['id'] }
      #   payload['records']&.filter_map { |r| r['name'] }
      #
      #   # good — Array() wraps nil as an empty array
      #   Array(response['items']).each { |item| process(item) }
      #
      #   # good — nil fallback with ||
      #   (response['items'] || []).each { |item| process(item) }
      #
      #   # good — safe navigation breaks the chain before enumerable
      #   response['items']&.each { |item| process(item) }
      #
      #   # good — wrapped in begin/rescue
      #   begin
      #     response['items'].each { |item| process(item) }
      #   rescue NoMethodError
      #     []
      #   end
      class ResponseBracketAccessWithoutNilFallback < Base
        MSG = 'Bracket access on response/result variable chained with `.method_name` without nil fallback. ' \
              'Use `Array(%<access>s)` or `%<access>s || []` to handle missing keys.'

        # Variable names that commonly hold API responses or parsed JSON.
        # Same list as ChainedHashAccessWithoutDig::TARGET_NAMES.
        TARGET_NAMES = %i[response payload result data json body].freeze

        # Ivar equivalents: @response, @payload, etc.
        TARGET_IVAR_NAMES = %i[@response @payload @result @data @json @body].freeze

        # Methods that iterate or chain on a collection — calling these on nil
        # raises NoMethodError.
        ITERABLE_METHODS = %i[
          each map collect select reject filter filter_map flat_map
          reduce inject each_with_index each_with_object
          any? all? none? one? count min max min_by max_by
          sort sort_by group_by partition tally uniq compact flatten
          first last size length to_a
        ].freeze

        # The `on_send` hook fires for every method call. We look for calls to
        # iterable methods whose receiver is a `Hash#[]` access on a target-named
        # variable, without a nil guard.
        def on_send(node)
          return if in_test_file?
          return unless ITERABLE_METHODS.include?(node.method_name)

          receiver = node.receiver
          return unless receiver&.send_type? && receiver.method_name == :[]
          return unless string_key?(receiver)
          return unless target_named_receiver?(receiver.receiver)
          return if wrapped_in_array?(receiver)
          return if safe_navigation?(node)
          return if inside_rescue?(node)
          return if chained_with_fallback?(node)

          add_offense(node, message: format(MSG, access: receiver.source))
        end

        private

        def string_key?(bracket_node)
          arg = bracket_node.arguments.first
          arg&.str_type?
        end

        # Check whether the innermost receiver is a target-named lvar, ivar, or
        # bare method call.
        def target_named_receiver?(node)
          case node&.type
          when :lvar
            TARGET_NAMES.include?(node.children[0])
          when :ivar
            TARGET_IVAR_NAMES.include?(node.children[0])
          when :send
            # Bare method call: (send nil :response)
            node.receiver.nil? && TARGET_NAMES.include?(node.method_name)
          else
            false
          end
        end

        # `Array(response['items'])` — the bracket access is wrapped in an
        # Array() call, which coerces nil to [].
        def wrapped_in_array?(bracket_node)
          parent = bracket_node.parent
          return false unless parent&.send_type?
          return false unless parent.method_name == :Array

          parent.receiver.nil? # Array() is a kernel method, no receiver
        end

        # Safe navigation on the iterable call (`response['items']&.each`) or
        # on the bracket access itself (`response&.[]('items')`) guards nil.
        def safe_navigation?(iterable_node)
          return true if iterable_node.csend_type?

          # Also check if the bracket access receiver uses safe navigation.
          bracket_receiver = iterable_node.receiver
          bracket_receiver&.csend_type?
        end

        # Inside a begin/rescue block — the rescue clause handles the nil error.
        def inside_rescue?(node)
          node.each_ancestor(:rescue).any?
        end

        # `(response['items'] || []).each` — the `||` with an Array literal
        # provides a nil fallback. We check if the bracket access's parent is an
        # `or` node with an array literal on the right side.
        def chained_with_fallback?(iterable_node)
          bracket = iterable_node.receiver
          return false unless bracket

          parent = bracket.parent
          return false unless parent&.or_type?

          # The `or` node: (or bracket_access array_literal)
          right = parent.children[1]
          right&.array_type?
        end

        def in_test_file?
          processed_source.file_path&.match?(/(_test\.rb|spec\.rb|test_.*\.rb)\z/)
        end
      end
    end
  end
end
