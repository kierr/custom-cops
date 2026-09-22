# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects rescue handlers that duplicate a method call from the try body
      # after performing some fixup (like reassigning a variable). The fixup
      # should be followed by Ruby's `retry` keyword instead of re-executing
      # the same call manually.
      #
      # This pattern typically arises when handling recoverable errors (e.g.,
      # Redis NOSCRIPT, expired tokens) where the fix is to reload/renew
      # a resource and then redo the original operation. Using `retry` is
      # safer because it re-executes the entire method body, avoiding subtle
      # drift between the original and duplicated code.
      #
      # Only flags when a rescue body contains a send node whose method name
      # matches a top-level send in the try body. Does not flag when the
      # rescue body uses `retry` already.
      #
      # @example
      #
      #   # bad — duplicated evalsha call in rescue
      #   def execute_lua(operation, args)
      #     @redis.evalsha(@sha, keys: [], argv: [operation] + args)
      #   rescue Redis::CommandError => e
      #     raise unless e.message.include?('NOSCRIPT')
      #     @sha = load_script
      #     @redis.evalsha(@sha, keys: [], argv: [operation] + args)
      #   end
      #
      #   # good — use retry to re-execute the method body
      #   def execute_lua(operation, args)
      #     @redis.evalsha(@sha, keys: [], argv: [operation] + args)
      #   rescue Redis::CommandError => e
      #     raise unless e.message.include?('NOSCRIPT')
      #     @sha = load_script
      #     retry
      #   end
      #
      class RescueDuplicatesTryBody < Base
        MSG = 'Rescue handler duplicates a method call from the try body. Use `retry` after fixup instead of re-executing the call manually.'

        def on_resbody(node)
          return if uses_retry?(node)
          return if node.body.nil?

          try_sends = collect_try_sends(node)
          return if try_sends.empty?

          rescue_sends = collect_send_names(node.body)
          duplicated = rescue_sends & try_sends
          return if duplicated.empty?

          add_offense(node, message: MSG)
        end

        private

        # The try body is stored in the rescue node (parent of resbody).
        # AST: (rescue try_body (resbody ...) ...) — try_body is rescue.children[0].
        # The rescue node's parent is the def/kwbegin.
        def collect_try_sends(resbody_node)
          rescue_node = resbody_node.parent
          return [] unless rescue_node && rescue_node.type == :rescue

          try_body = rescue_node.children.first
          return [] unless try_body

          collect_send_names(try_body)
        end

        # Collect unique method names from send nodes, recursing one level
        # into begin blocks but not into if/else branches or blocks.
        def collect_send_names(node)
          return [] unless node

          case node.type
          when :send
            [node.method_name]
          when :begin
            node.children.flat_map { |child| collect_send_names(child) }
          when :block
            collect_send_names(node.send_node)
          else
            []
          end
        end

        def uses_retry?(resbody_node)
          return false unless resbody_node.body

          find_retry?(resbody_node.body)
        end

        def find_retry?(node)
          return false unless node

          case node.type
          when :retry
            true
          when :begin
            node.children.any? { |child| find_retry?(child) }
          when :if
            [node.children[1], node.children[2]].compact.any? { |branch| find_retry?(branch) }
          else
            false
          end
        end
      end
    end
  end
end
