# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Detects `after_create` and `before_create` callbacks that perform external
      # side effects (Kafka produce, HTTP calls, graph mutations, notification
      # service calls). These run inside the transaction and can fire before commit,
      # causing visible-before-commit anomalies and failed side effects on rollback.
      #
      # The cop resolves callback method names (symbol args) to their `def` nodes
      # within the same file, then inspects the method body for external calls.
      # It also follows bare method calls (no receiver) transitively within the
      # same file, catching the common pattern where the callback delegates to an
      # _impl method that contains the actual external call.
      #
      # It does NOT flag callbacks that only perform DB writes (AR create/update/save),
      # which are safe within the transaction.
      #
      # @example
      #
      #   # bad -- Kafka produce inside transaction
      #   class Webhook < ApplicationRecord
      #     after_create :publish_event
      #
      #     def publish_event
      #       KafkaProducer.produce_async(topic: 'webhooks', key: id, payload: data)
      #     end
      #   end
      #
      #   # bad -- external call via delegation (transitive resolution)
      #   class Relation < ApplicationRecord
      #     after_create :create_edge
      #
      #     def create_edge
      #       ActiveSupport::Notifications.instrument('edge.create') { create_edge_impl }
      #     end
      #
      #     def create_edge_impl
      #       GraphClient.create_vertex(object_id: id, object_type: type)
      #     end
      #   end
      #
      #   # good -- DB-only callback (safe inside transaction)
      #   class Entity < ApplicationRecord
      #     after_create :update_counter
      #
      #     def update_counter
      #       update_columns(counter: counter + 1)
      #     end
      #   end
      #
      #   # good -- already using after_commit
      #   class Address < ApplicationRecord
      #     after_commit :normalize_async, on: :create
      #   end
      #
      class AfterCreateInsteadOfAfterCommit < Base
        MSG = 'Use `after_commit` instead of `%<callback>s` for external side effects in `%<method>s`. ' \
              'Transaction-internal callbacks can fire before commit, causing visible-before-commit anomalies ' \
              'and failed side effects on rollback.'

        CALLBACK_METHODS = %i[after_create before_create].freeze

        # Receiver patterns (as constant names) that indicate external service calls.
        # Any method call on these receivers is an external side effect.
        # Extend via .rubocop.yml ExternalReceiverPatterns.
        EXTERNAL_RECEIVER_PATTERNS = %i[KafkaProducer GraphClient EventBus].freeze

        # Method names that are safe DB operations -- not flagged even inside after_create.
        SAFE_DB_METHODS = %i[
          save save! create create! create_or_find_by create_or_find_by!
          update update! update_columns update_column update_all
          upsert upsert_all insert insert! insert_all insert_all!
          increment! decrement! touch touch_all
          delete delete_all destroy destroy_all destroy!
          reload
        ].freeze

        def on_new_investigation
          return unless processed_source.ast

          callback_methods = collect_callback_method_names
          return if callback_methods.empty?

          all_method_nodes = collect_all_method_nodes

          callback_methods.each do |method_name, callback_name|
            def_node = all_method_nodes[method_name]
            next unless def_node
            next unless def_node.body

            visited = Set.new
            scan_body_transitive(def_node.body, callback_name, method_name.to_s, all_method_nodes, visited)
          end
        end

        private

        # Collect after_create/before_create callback method names from the AST.
        # Returns { method_name_sym => callback_name_sym }, e.g. { register_world_object: :after_create }.
        def collect_callback_method_names
          methods = {}

          processed_source.ast.each_node(:send) do |send_node|
            next unless CALLBACK_METHODS.include?(send_node.method_name)
            next unless send_node.receiver.nil?

            first_arg = send_node.arguments.first
            next unless first_arg

            name = extract_method_name(first_arg)
            methods[name] = send_node.method_name if name
          end

          methods
        end

        def extract_method_name(arg)
          case arg.type
          when :sym
            arg.value
          when :str
            arg.value.to_sym
          end
        end

        # Collect ALL def nodes in the file for transitive resolution.
        def collect_all_method_nodes
          nodes = {}

          processed_source.ast.each_node(:def) do |def_node|
            method_name = def_node.method_name
            next if nodes.key?(method_name)

            nodes[method_name] = def_node
          end

          nodes
        end

        # Walk the method body for external effects, and follow bare method calls
        # (no receiver) transitively into their def nodes.
        def scan_body_transitive(body_node, callback_name, method_name, all_method_nodes, visited)
          body_node.each_node(:send) do |send_node|
            next if safe_db_operation?(send_node)

            if external_side_effect?(send_node)
              add_offense(send_node.loc.selector, message: format(MSG, callback: callback_name, method: method_name))
              next
            end

            # Follow bare method calls (no receiver) transitively.
            next if send_node.receiver
            next if visited.include?(send_node.method_name)

            target_def = all_method_nodes[send_node.method_name]
            next unless target_def
            next unless target_def.body

            visited.add(send_node.method_name)
            scan_body_transitive(target_def.body, callback_name, method_name, all_method_nodes, visited)
          end
        end

        # Check if the send node is a known-safe DB operation.
        def safe_db_operation?(node)
          SAFE_DB_METHODS.include?(node.method_name)
        end

        # Determine if a send node represents an external side effect.
        # Conservative: must match a known external receiver pattern.
        # Any method call on a configured external receiver (e.g. KafkaProducer, GraphClient, EventBus)
        # crosses a process boundary and should not run inside a transaction.
        def external_side_effect?(node)
          external_receiver?(node)
        end

        # Check the receiver chain for known external service patterns.
        # Matches patterns like:
        #   KafkaProducer.produce_async(...)
        #   GraphClient.create_vertex(...)
        #   MyApp::GraphClient.call(...)
        def external_receiver?(node)
          receiver = node.receiver
          return false unless receiver

          chain = receiver_chain(receiver)
          chain.any? { |name| EXTERNAL_RECEIVER_PATTERNS.include?(name) }
        end

        # Extract the chain of constant/module names from a receiver node.
        def receiver_chain(node)
          names = []

          current = node
          while current
            case current.type
            when :const
              names << current.children[1]
              current = current.children[0]
            when :send
              names << current.method_name
              current = current.receiver
            else
              break
            end
          end

          names
        end
      end
    end
  end
end
