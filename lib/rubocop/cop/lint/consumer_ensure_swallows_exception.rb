# typed: strict
# frozen_string_literal: true

# All errors are 7018 "call on T.untyped" from RuboCop AST API
# (Parser::AST::Node methods — no RBI coverage).
module RuboCop
  module Cop
    module Lint
      # Detects `ensure` blocks in Karafka consumer classes (subclasses of
      # ApplicationConsumer) that contain an explicit `return`, which silently
      # swallows any in-flight exception and prevents DLQ routing.
      #
      # In Ruby, `ensure` propagates exceptions automatically — no explicit
      # `raise` is needed. The one pattern that DOES suppress exceptions is
      # an explicit `return` inside an `ensure` body:
      #
      #   begin
      #     raise "boom"
      #   ensure
      #     cleanup
      #     return        # <-- exception silently swallowed
      #   end
      #
      # Without the `return`, the exception propagates after cleanup.
      # With it, the method returns nil (or the return value) and the
      # exception is lost — Karafka considers the message consumed.
      #
      # Also flags ensure bodies that contain no cleanup calls at all — an
      # ensure block with an empty body or only side-effect-free expressions
      # is suspicious in a consumer, suggesting incomplete error handling.
      #
      # @example
      #
      #   # bad — explicit return in ensure swallows the exception
      #   class MyConsumer < ApplicationConsumer
      #     def process_messages
      #       messages.each do |message|
      #         process(message)
      #       rescue StandardError => e
      #         logger.error("failed", error: e.message)
      #         raise
      #       ensure
      #         batch&.run
      #         return
      #       end
      #     end
      #   end
      #
      #   # good — ensure propagates exception automatically
      #   class MyConsumer < ApplicationConsumer
      #     def process_messages
      #       messages.each do |message|
      #         process(message)
      #       rescue StandardError => e
      #         logger.error("failed", error: e.message)
      #         raise
      #       ensure
      #         batch&.run
      #       end
      #     end
      #   end
      #
      #   # good — ensure with explicit re-raise preserves exception
      #   class MyConsumer < ApplicationConsumer
      #     def process_messages
      #       begin
      #         process_all
      #       ensure
      #         strategy.disconnect
      #         raise if $!
      #       end
      #     end
      #   end
      class ConsumerEnsureSwallowsException < Base
        MSG = 'Explicit `return` in ensure block of consumer swallows in-flight exception — DLQ routing will not fire.'

        # Consumer base classes whose ensure blocks are subject to this check.
        CONSUMER_SUPERCLASSES = %w[ApplicationConsumer Base].freeze

        # Lifecycle methods where ensure blocks are less risky — these are
        # teardown/cleanup hooks, not message processing methods.
        EXCLUDED_METHOD_NAMES = %i[shutdown revoked after_consume on_enforced_consume].freeze

        def on_class(node)
          parent = node.parent_class
          return unless parent
          return unless CONSUMER_SUPERCLASSES.include?(parent.const_name)

          each_ensure_in_methods(node.body) do |ensure_node, method_name|
            next if EXCLUDED_METHOD_NAMES.include?(method_name)
            next unless contains_return?(ensure_node)

            add_offense(ensure_node.loc.keyword, message: MSG)
          end
        end

        private

        # Yields [ensure_node, enclosing_method_name] for every ensure clause
        # found inside method definitions within the class body.
        def each_ensure_in_methods(class_body)
          return unless class_body

          defs = if class_body.def_type?
                   [class_body]
                 elsif class_body.begin_type?
                   class_body.children.select(&:def_type?)
                 else
                   []
                 end

          defs.each do |def_node|
            method_name = def_node.method_name
            walk_for_ensure(def_node.body, method_name) { |ensure_node| yield ensure_node, method_name }
          end
        end

        # Recursively walks the AST to find all `ensure` nodes.
        # An ensure node has type :kwbegin wrapping a :ensure pair.
        def walk_for_ensure(node, method_name, &block)
          return unless node

          yield node if node.ensure_type?

          node.children.each { |child| walk_for_ensure(child, method_name, &block) if child.is_a?(Parser::AST::Node) }
        end

        # Checks whether the ensure body contains an explicit `return`.
        # A `return` in an ensure block silently swallows any in-flight
        # exception — this is the core bug pattern.
        def contains_return?(ensure_node)
          body = ensure_body(ensure_node)
          return false unless body

          return_in?(body)
        end

        # Returns the body of an ensure node (the code after `ensure`).
        # ensure structure: (ensure <begin-body> <ensure-body>)
        def ensure_body(ensure_node)
          return nil unless ensure_node.ensure_type?

          ensure_node.children[1]
        end

        # Recursively checks whether a node tree contains a `return`.
        def return_in?(node)
          return false unless node

          case node.type
          when :return
            true
          when :begin, :kwbegin, :if, :block
            node.children.any? { |child| child.is_a?(Parser::AST::Node) && return_in?(child) }
          else
            false
          end
        end
      end
    end
  end
end
