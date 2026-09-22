# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `.sample` calls on dynamically-computed arrays where the result
      # is used without a nil fallback. `Array#sample` returns `nil` on empty
      # arrays. When the receiver is a method call or variable that could produce
      # an empty array, the nil result crashes downstream with NoMethodError.
      #
      # Excludes safe patterns: literal arrays (caller controls emptiness),
      # safe navigation (`&.sample`), `T.cast(... T.nilable(...))` wrapping,
      # `||` fallback, constants (known non-empty by convention), and
      # ternary/bounds-checked guards (`pool.size == 1 ? pool.first : pool.sample`).
      #
      # @example
      #
      #   # bad — proxies may be empty, sample returns nil
      #   proxy = proxies.sample
      #
      #   # bad — chained method call may return empty array
      #   fetch_result.data.sample
      #
      #   # good — safe navigation short-circuits on nil receiver
      #   fetch_result.data&.sample
      #
      #   # good — T.cast with T.nilable acknowledges nil possibility
      #   T.cast(proxies.sample, T.nilable(String))
      #
      #   # good — || fallback handles nil
      #   proxies.sample || default_proxy
      #
      #   # good — literal array, caller controls emptiness
      #   [49_900, 59_900, 69_900].sample
      #
      #   # good — constant receiver, known non-empty by convention
      #   S24_ACCOUNTS.sample
      #
      class SampleWithoutFallback < Base
        MSG = '`.sample` on dynamic array without nil fallback. `Array#sample` returns nil when empty — use `&.sample`, `T.cast(... T.nilable(...))`, or `|| fallback`.'

        def on_send(node)
          return unless node.method_name == :sample
          # .sample with arguments (e.g., .sample(3)) returns an Array, not nil
          return if node.arguments.any?
          # Safe navigation (&.sample) already acknowledges nil receiver
          return if node.csend_type?

          receiver = node.receiver
          return unless receiver
          # Literal arrays — caller controls emptiness
          return if receiver.array_type?
          # Constants (e.g., S24_ACCOUNTS) are known non-empty by convention
          return if receiver.const_type?

          # Only flag when the receiver is a method call or variable that could
          # produce an empty array. Skip simple lvars — they are typically
          # assigned nearby and the nil risk is caught by NilChainingWithoutGuard.
          return unless receiver.send_type? || receiver.csend_type?

          return if protected_by_fallback?(node)

          add_offense(node)
        end

        private

        # Check whether the .sample call is wrapped in a recognized nil-safe pattern.
        def protected_by_fallback?(sample_node)
          parent = sample_node.parent
          return false unless parent

          # T.cast(x.sample, T.nilable(...)) — explicit nil acknowledgment
          return true if t_cast_with_nilable?(parent, sample_node)

          # x.sample || fallback — or-fallback handles nil
          return true if or_fallback?(parent, sample_node)

          # T.must(x.sample) — asserts non-nil (deliberate choice)
          return true if t_must_wrap?(parent, sample_node)

          # x.sample.then { ... } — .then on nil is safe (NilClass#then exists)
          # but also consider .sample || {} patterns
          return true if ternary_guard?(parent, sample_node)

          false
        end

        # T.cast(expr, T.nilable(...)) wrapping.
        def t_cast_with_nilable?(parent, sample_node)
          return false unless parent.send_type?
          return false unless parent.method_name == :cast
          return false unless parent.receiver

          receiver = parent.receiver
          return false unless receiver.const_type?
          return false unless receiver.source == 'T'

          # The sample node must be the first argument to T.cast
          parent.arguments.first == sample_node
        end

        # x.sample || fallback — the `||` operator provides a nil fallback.
        def or_fallback?(parent, sample_node)
          return false unless parent.or_type?

          # sample_node must be the LHS of the ||
          parent.children.first == sample_node
        end

        # T.must(x.sample) — deliberate non-nil assertion.
        def t_must_wrap?(parent, sample_node)
          return false unless parent.send_type?
          return false unless parent.method_name == :must

          receiver = parent.receiver
          return false unless receiver&.const_type? && receiver.source == 'T'

          parent.arguments.first == sample_node
        end

        # Ternary guard: pool.length == 1 ? pool.first : pool.sample
        # The ternary condition checks bounds, making .sample safe.
        def ternary_guard?(parent, sample_node)
          return false unless parent.if_type?

          # sample_node must be in the else branch
          parent.children[2] == sample_node
        end
      end
    end
  end
end
