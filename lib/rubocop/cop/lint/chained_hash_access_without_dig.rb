# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects chained `Hash#[]` access on response/payload/result variables:
      # `response['hits']['hits']` or `payload['source']['topic']`. When the
      # first key is missing, `nil['key']` raises `TypeError`. The existing
      # `NilChainingWithoutGuard` covers the two-statement pattern
      # (`var = hash['key']; var['nested']`) but not the inline chained case.
      #
      # @example
      #
      #   # bad — nil['key'] raises TypeError if 'hits' is missing
      #   response['hits']['hits']
      #   payload['source']['topic']
      #
      #   # good — dig returns nil for missing keys instead of raising
      #   response.dig('hits', 'hits')
      #   payload&.dig('source', 'topic')
      #
      #   # good — safe navigation breaks the chain
      #   response&.[]('hits')
      #
      #   # good — literal hash access is safe (keys are known)
      #   { 'a' => { 'b' => 1 } }['a']['b']
      class ChainedHashAccessWithoutDig < Base
        MSG = 'Use `dig` instead of chained `[]` access — `nil["key"]` raises TypeError when an intermediate key is missing.'

        # Variable names that commonly hold API responses or parsed JSON where
        # key presence is not guaranteed. Scoping to these names avoids flagging
        # struct-style access on domain objects with known shapes.
        TARGET_NAMES = %i[response payload result data json body].freeze

        # Ivar equivalents: @response, @payload, etc.
        TARGET_IVAR_NAMES = %i[@response @payload @result @data @json @body].freeze

        def on_send(node)
          return unless node.method_name == :[]
          return unless (receiver = node.receiver)
          return unless receiver.send_type? && receiver.method_name == :[]
          return if in_test_file?
          return unless target_named_receiver?(innermost_receiver(receiver))
          return if uses_safe_navigation?(node)
          return if any_link_uses_dig?(node)

          add_offense(node)
        end

        private

        # Walk to the innermost receiver in a chain of `[]` calls.
        # For `response['a']['b']`, returns the node for `response`.
        def innermost_receiver(node)
          receiver = node.receiver
          receiver = receiver.receiver while receiver&.send_type? && receiver.method_name == :[]
          receiver
        end

        # Check whether the innermost receiver is a local variable, instance variable,
        # or bare method call with a name in TARGET_NAMES.
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

        # Walk the receiver chain looking for safe navigation (`&.`) -- if any
        # link uses it, the chain is guarded against TypeError.
        def uses_safe_navigation?(node)
          receiver = node.receiver
          while receiver&.send_type? || receiver&.csend_type?
            return true if receiver.csend_type?

            receiver = receiver.receiver
          end
          false
        end

        # Walk the receiver chain looking for `dig` -- if any link uses `dig`,
        # the chain is safe.
        def any_link_uses_dig?(node)
          receiver = node.receiver
          while receiver
            return true if receiver.send_type? && receiver.method_name == :dig
            return true if receiver.csend_type? && receiver.method_name == :dig

            receiver = receiver.respond_to?(:receiver) ? receiver.receiver : nil
          end
          false
        end

        def in_test_file?
          processed_source.file_path&.match?(/(_test\.rb|spec\.rb|test_.*\.rb)\z/)
        end
      end
    end
  end
end
