# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Detects multi-line strings in logger calls, which break log aggregation.
      # Structured logging systems split multiline entries, causing partial messages.
      # Use single-line messages with structured keyword arguments.
      #
      # @example
      #
      #   # bad
      #   logger.warn("StrategyRegistry: named validator '#{v}' for #{cc}.#{k} is not registered,\n  falling back to regex")
      #
      #   # good
      #   logger.warn('StrategyRegistry: named validator not registered, falling back to regex',
      #     validator: v, country_code: cc, kind: k)
      class SingleLineStructured < Base
        extend AutoCorrector

        MSG = 'Multi-line string in log call breaks aggregation. Use single-line message with structured keyword arguments.'

        LOG_METHODS = %i[info warn error debug fatal].freeze

        def_node_matcher :log_call_with_string?, <<~PATTERN
          (send {(send nil? :logger) (ivar :logger) (lvar :logger) (const ... :LOGGER)} LOG_METHODS $(str ...) ...)
        PATTERN

        def on_send(node)
          return unless LOG_METHODS.include?(node.method_name)

          return unless logger_receiver?(node)

          first_arg = node.first_argument
          return unless first_arg

          return unless string_with_newline?(first_arg)

          add_offense(first_arg) do |corrector|
            # Replace \n and embedded newlines with spaces
            source = first_arg.source
            corrected = source.gsub('\\n', ' ').gsub(/\n\s*/, ' ').gsub(/\s{2,}/, ' ')
            corrector.replace(first_arg, corrected)
          end
        end

        private

        def logger_receiver?(node)
          receiver = node.receiver
          return false unless receiver
          return true if receiver.send_type? && receiver.method_name == :logger
          return true if receiver.ivar_type? && receiver.name == :@logger
          return true if receiver.lvar_type? && receiver.name == :logger
          return true if receiver.const_type?

          false
        end

        def string_with_newline?(node)
          case node.type
          when :str
            node.value.include?("\n")
          when :dstr
            node.children.any? do |child|
              case child.type
              when :str
                child.value.include?("\n")
              # Non-string children (interpolations etc.) never contain literal newlines
              else
                false
              end
            end
          else
            false
          end
        end
      end
    end
  end
end
