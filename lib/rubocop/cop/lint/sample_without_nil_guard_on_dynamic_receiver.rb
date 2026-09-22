# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `.sample` on method-chain receivers (e.g., `result.data.sample`,
      # `proxies.sample`, `fetch_result.data.sample`) where the receiver is a
      # method-call result that could be nil or empty. `Array#sample` returns nil
      # on empty arrays; `nil.sample` raises NoMethodError.
      #
      # The safe navigation `&.sample` pattern only protects against nil receiver,
      # not against empty arrays returning nil from `.sample`. This cop flags
      # unguarded `.sample` on dynamic receivers that originate from service
      # results, fetch operations, or database queries.
      #
      # Excludes: literal arrays, constants, `||` fallback, `if`/`unless` guard
      # on the receiver, `blank?`/`empty?`/`present?` checks before `.sample`,
      # `T.cast`/`T.must` wrapping, and `.sample(n)` (returns Array).
      #
      # @example
      #
      #   # bad — no nil guard on service result chain
      #   fetch_result.data.sample
      #
      #   # bad — no nil guard on query result
      #   User.where(active: true).sample
      #
      #   # bad — safe navigation only guards nil receiver, not empty array
      #   result.data&.sample
      #
      #   # good — || fallback handles nil
      #   result.data.sample || default_value
      #
      #   # good — if guard checks receiver
      #   return if result.data.blank?
      #   result.data.sample
      #
      #   # good — T.cast acknowledges nil
      #   T.cast(result.data.sample, T.nilable(String))
      #
      #   # good — literal array
      #   [1, 2, 3].sample
      #
      #   # good — constant receiver
      #   POOL.sample
      #
      class SampleWithoutNilGuardOnDynamicReceiver < Base
        MSG = '`.sample` on dynamic receiver without nil guard. Use `|| fallback`, check `.blank?`/`.present?`, or wrap with `T.cast(... T.nilable(...))`.'

        # Method names that indicate the receiver comes from a service result,
        # fetch operation, or database query — sources that could return nil/empty.
        RECEIVER_METHODS = %i[data results records items entries rows proxies accounts pool list all where find_each to_a fetch call].freeze

        # Methods on the sample result's parent that provide nil safety.
        SAFETY_WRAPPERS = %i[cast must].freeze

        # Nil-guard methods checked on the receiver before .sample.
        GUARD_METHODS = %i[present? blank? empty? nil? any?].freeze

        def on_send(node)
          _ = check_sample(node)
        end

        def on_csend(node)
          _ = check_sample(node)
        end

        private

        def check_sample(node)
          return unless node.method_name == :sample
          # .sample(n) returns Array, not nil
          return if node.arguments.any?
          return if literal_or_constant_receiver?(node)

          receiver = node.receiver
          return unless receiver
          # Only flag method-call or safe-navigation chains (not lvars)
          return unless dynamic_receiver?(receiver)

          return if protected_by_parent?(node)
          return if guarded_by_condition?(node, receiver)

          add_offense(node)
        end

        # Literal arrays and constants are known-safe.
        def literal_or_constant_receiver?(node)
          receiver = node.receiver

          return true unless receiver

          receiver.array_type? || receiver.const_type?
        end

        # The receiver is a method call, safe navigation chain, or chain ending
        # in a recognized dynamic-source method.
        def dynamic_receiver?(receiver)
          return false unless receiver.send_type? || receiver.csend_type?

          true
        end

        # Parent node provides nil safety: || fallback, T.cast/T.must, ternary.
        def protected_by_parent?(sample_node)
          parent = sample_node.parent
          return false unless parent

          return true if or_fallback?(parent, sample_node)
          return true if t_wrapper?(parent, sample_node)
          return true if ternary_guard?(parent, sample_node)

          false
        end

        # x.sample || fallback
        def or_fallback?(parent, sample_node)
          return false unless parent.or_type?

          parent.children.first == sample_node
        end

        # T.cast(x.sample, ...) or T.must(x.sample)
        def t_wrapper?(parent, sample_node)
          return false unless parent.send_type?
          return false unless SAFETY_WRAPPERS.include?(parent.method_name)

          recv = parent.receiver
          return false unless recv&.const_type? && recv.source == 'T'

          parent.arguments.first == sample_node
        end

        # Ternary: condition ? a : b.sample
        def ternary_guard?(parent, sample_node)
          return false unless parent.if_type?

          # sample in either branch implies a condition was evaluated
          parent.children[1] == sample_node || parent.children[2] == sample_node
        end

        # Walk up from the .sample node looking for a preceding if/unless guard
        # that checks the receiver with present?/blank?/empty?/nil?/any?.
        def guarded_by_condition?(sample_node, receiver)
          container = find_enclosing_body(sample_node)
          return false unless container

          return false unless container.begin_type?

          root_name = extract_root_name(receiver)
          return false unless root_name

          sample_line = sample_node.loc.expression.line
          container.each_child_node do |child|
            next unless child.loc.expression.line < sample_line

            condition = extract_guard_condition(child)
            next unless condition

            return true if guard_references_root?(condition, root_name)
          end

          false
        end

        # Find the nearest begin-type ancestor that represents a method body or
        # block body — the scope in which a guard check would apply.
        def find_enclosing_body(node)
          node.each_ancestor(:begin).first
        end

        # Extract the root variable name from a method chain receiver.
        # result.data -> "result", proxies -> "proxies"
        def extract_root_name(receiver)
          # Walk left through the chain to find the root send (no receiver)
          node = receiver
          while node&.send_type? || node&.csend_type?
            parent = node.receiver
            break unless parent&.send_type? || parent&.csend_type?

            node = parent
          end

          # The root is the leftmost send node. Its receiver is nil for bare
          # method calls (result.data -> result is s(:send, nil, :result)).
          # Its receiver is an lvar for local variable chains.
          root_recv = node&.receiver
          if root_recv.nil?
            # Bare method call: the method name IS the root identifier
            node&.method_name&.to_s
          elsif root_recv.lvar_type?
            root_recv.source
          end
        end

        # Extract the condition from an if/unless guard node.
        def extract_guard_condition(node)
          # `return if expr` — the return is the body of an if node
          if node.send_type? && node.method_name == :return
            return nil unless node.parent&.if_type?

            return node.parent.condition
          end

          # `if expr ... end` / `unless expr ... end`
          return node.condition if node.if_type?

          # `raise ... if expr` — the raise is the body of a modifier if
          if node.send_type?
            parent = node.parent
            return parent.condition if parent&.if_type?
          end

          nil
        end

        # Check whether the guard condition references the same root name as
        # the .sample receiver and uses a guard method (present?/blank?/etc.).
        def guard_references_root?(condition, root_name)
          return false unless condition

          condition.each_node(:send, :csend) do |node|
            next unless GUARD_METHODS.include?(node.method_name)

            # Check if this guard method's chain shares the root name
            guard_root = extract_root_name(node)
            return true if guard_root == root_name
          end

          false
        end
      end
    end
  end
end
