# typed: strict
# frozen_string_literal: true

# All errors are 7018 "call on T.untyped" from RuboCop AST API
# (Parser::AST::Node methods — no RBI coverage).
module RuboCop
  module Cop
    module Karafka
      # Detects `rescue` blocks in Karafka consumer classes (subclasses of
      # ApplicationConsumer) where the body logs the error but never calls
      # `raise`, `mark_as_consumed!`/`mark_as_consumed`, or dispatches to DLQ.
      #
      # When a consumer rescues without re-raising, Karafka considers the message
      # successfully consumed — failed messages are silently lost instead of being
      # routed to the DLQ. Each rescue block must terminate in one of:
      #
      #   - `raise` (bare or with argument) — re-raises for DLQ routing
      #   - `mark_as_consumed` / `mark_as_consumed!` — explicitly marks as consumed
      #   - `produce_async` / `produce_sync` with a DLQ topic — manual DLQ dispatch
      #
      # Excluded: `on_enforced_consume` and `after_consume` hooks where
      # logging-only rescue is acceptable (cleanup/teardown, not message processing).
      #
      # @example
      #   # bad — message silently dropped, never reaches DLQ
      #   class MyConsumer < ApplicationConsumer
      #     def process_messages
      #       messages.each do |message|
      #         process(message)
      #       rescue StandardError => e
      #         logger.error("processing failed", error: e.message)
      #       end
      #     end
      #   end
      #
      #   # good — re-raises for DLQ routing
      #   class MyConsumer < ApplicationConsumer
      #     def process_messages
      #       messages.each do |message|
      #         process(message)
      #       rescue StandardError => e
      #         logger.error("processing failed", error: e.message)
      #         raise
      #       end
      #     end
      #   end
      #
      #   # good — explicitly marks consumed (intentional skip)
      #   class MyConsumer < ApplicationConsumer
      #     def process_messages
      #       messages.each do |message|
      #         process(message)
      #       rescue ArgumentError => e
      #         logger.error("bad payload", error: e.message)
      #         mark_as_consumed(message)
      #       end
      #     end
      #   end
      class ConsumerRescueWithoutReraise < Base
        MSG = 'Rescue block in consumer logs error but never re-raises or marks consumed. Failed messages will be silently lost instead of reaching DLQ.'

        CONSUMER_SUPERCLASSES = %w[ApplicationConsumer Base].freeze

        # Methods that indicate the rescue block properly handles the failure.
        # `raise` re-raises for DLQ routing; `mark_as_consumed` explicitly
        # acknowledges; `produce_async`/`produce_sync` dispatch to DLQ.
        # `after_consume` is recognized as terminal because it calls
        # `mark_as_consumed` in ApplicationConsumer (typed wrapper).
        TERMINAL_METHODS = %i[raise mark_as_consumed mark_as_consumed! after_consume].freeze

        DLQ_DISPATCH_METHODS = %i[produce_async produce_sync].freeze

        # Logging method names that indicate error-aware rescue bodies.
        LOG_METHODS = %i[error warn fatal].freeze

        # Method names that are themselves logging helpers (e.g., log_exception
        # in ApplicationConsumer) — presence indicates error-aware rescue body.
        LOG_HELPER_METHODS = %i[log_exception].freeze

        # Method names where logging-only rescue is acceptable — these are
        # lifecycle hooks or utility helpers, not message processing methods.
        # ES adapter helpers (es_mget, write_bulk, fetch_existing_docs) swallow
        # ES errors for graceful degradation — the message still processes
        # successfully without the ES data. Non-ES errors propagate to the
        # consumer's process_messages for DLQ routing.
        EXCLUDED_METHOD_NAMES = %i[on_enforced_consume after_consume es_mget write_bulk fetch_existing_docs].freeze

        def on_class(node)
          parent = node.parent_class
          return unless parent
          return unless CONSUMER_SUPERCLASSES.include?(parent.const_name)

          each_rescue_body(node.body) do |rescue_node, method_name|
            next if EXCLUDED_METHOD_NAMES.include?(method_name)
            next if contains_terminal_call?(rescue_node)

            body = rescue_body(rescue_node)
            next unless body
            next unless contains_logging?(body)

            add_offense(rescue_node.loc.keyword, message: MSG)
          end
        end

        private

        # Yields [resbody_node, enclosing_method_name] for every rescue clause
        # found inside method definitions within the class body.
        def each_rescue_body(class_body)
          return unless class_body

          # class_body may be a single def or a begin block containing defs.
          defs = if class_body.def_type?
                   [class_body]
                 elsif class_body.begin_type?
                   class_body.children.select(&:def_type?)
                 else
                   []
                 end

          defs.each do |def_node|
            method_name = def_node.method_name
            walk_for_rescue(def_node.body, method_name) { |rescue_node| yield rescue_node, method_name }
          end
        end

        # Recursively walks the AST to find all `rescue` nodes.
        # A `rescue` node has type :rescue with structure:
        #   (rescue <begin-body> <resbody1> <resbody2> ... <else-node?>)
        # Each resbody has type :resbody.
        # Walks all children unconditionally — rescue blocks can appear nested inside
        # any expression (lvasgn, send args, T.cast, if branches, block bodies, etc.).
        def walk_for_rescue(node, method_name, &block)
          return unless node

          if node.rescue_type?
            node.children.each do |child|
              next unless child

              yield child if child.resbody_type?
            end
          end

          node.children.each { |child| walk_for_rescue(child, method_name, &block) if child.is_a?(Parser::AST::Node) }
        end

        # Returns the body of a resbody node (the code executed when rescue fires).
        # resbody structure: (resbody <exception-list> <variable> <body>)
        def rescue_body(resbody_node)
          return nil unless resbody_node.resbody_type?

          resbody_node.children[2]
        end

        # Checks whether the rescue body (or its nested children) contains a
        # terminal call: raise, mark_as_consumed, mark_as_consumed!, or
        # produce_async/produce_sync (DLQ dispatch).
        def contains_terminal_call?(resbody_node)
          body = rescue_body(resbody_node)
          return false unless body

          terminal_call_in?(body)
        end

        def terminal_call_in?(node)
          return false unless node

          case node.type
          when :send
            return true if TERMINAL_METHODS.include?(node.method_name)
            return true if DLQ_DISPATCH_METHODS.include?(node.method_name)

            false
          when :block
            node.children.each do |child|
              next unless child.is_a?(Parser::AST::Node)
              return true if terminal_call_in?(child)
            end
            false
          when :begin
            node.children.any? { |child| terminal_call_in?(child) }
          when :if
            # Both branches must contain terminal calls for the rescue to be
            # considered safe — otherwise one path may silently drop the message.
            true_branch = node.children[1]
            else_branch = node.children[2]
            if true_branch && else_branch
              terminal_call_in?(true_branch) && terminal_call_in?(else_branch)
            else
              false
            end
          else
            false
          end
        end

        # Checks whether the node tree contains a logging call. Recognizes:
        #   - logger.error/warn/fatal (ivar, lvar, send receiver)
        #   - Rails.logger.error/warn/fatal
        #   - SemanticLogger.error/warn/fatal
        #   - log_exception helper calls (ApplicationConsumer helper)
        def contains_logging?(node)
          return false unless node

          case node.type
          when :send
            logging_send?(node) || log_helper_call?(node)
          when :block
            contains_logging?(node.children.first) if node.children.first.is_a?(Parser::AST::Node)
          when :begin
            node.children.any? { |child| child.is_a?(Parser::AST::Node) && contains_logging?(child) }
          when :if
            node.children.any? { |child| child.is_a?(Parser::AST::Node) && contains_logging?(child) }
          else
            false
          end
        end

        # Validates receiver before matching log method names.
        # Accepts: logger.error, @logger.warn, Rails.logger.error, SemanticLogger.error
        def logging_send?(node)
          return false unless node.send_type?
          return false unless LOG_METHODS.include?(node.method_name)

          receiver = node.receiver
          return false unless receiver

          # logger.error (method call receiver)
          (receiver.send_type? && receiver.method_name == :logger) ||
            # @logger.error (instance variable)
            (receiver.ivar_type? && receiver.name == :@logger) ||
            # logger (local variable)
            (receiver.lvar_type? && receiver.name == :logger) ||
            # Rails.logger.error — const.send receiver
            (receiver.send_type? && receiver.receiver&.const_type? && receiver.method_name == :logger) ||
            # SemanticLogger.error — direct const receiver
            (receiver.const_type? && receiver.const_name == 'SemanticLogger')
        end

        # Matches bare helper calls like `log_exception('event', e)` which is
        # defined in ApplicationConsumer and logs at error level.
        def log_helper_call?(node)
          return false unless node.send_type?

          LOG_HELPER_METHODS.include?(node.method_name)
        end
      end
    end
  end
end
