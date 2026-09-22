# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `Time.zone.parse`, `Time.parse`, and `DateTime.parse` calls
      # that are not wrapped in a `rescue ArgumentError` (or broader) block.
      # These methods raise `ArgumentError` on invalid date strings; unhandled
      # exceptions crash the caller.
      #
      # The cop walks ancestors from each parse call looking for a surrounding
      # `rescue` node whose resbody catches `ArgumentError` or `StandardError`.
      # Frozen string literal arguments are excluded — they are known parseable
      # at load time.
      #
      # @example
      #
      #   # bad — raises ArgumentError on invalid date
      #   timestamp = Time.zone.parse(user_input)
      #
      #   # good — rescue handles the ArgumentError
      #   timestamp = begin
      #     Time.zone.parse(user_input)
      #   rescue ArgumentError
      #     nil
      #   end
      #
      #   # good — frozen string literal is always parseable
      #   timestamp = Time.zone.parse("2025-01-01")
      #
      #   # good — already inside a rescue ArgumentError block
      #   Time.parse(input)
      #   rescue ArgumentError => e
      #     nil
      class TimeParseWithoutRescue < Base
        MSG = 'Wrap `%<method>s` in a `rescue ArgumentError` block — it raises on invalid date strings.'

        # Method name that triggers the cop.
        PARSE_METHOD = :parse

        # Short const names for time-parsing receivers (as strings for comparison).
        RECEIVER_NAMES = %w[Time DateTime].freeze

        def on_send(node)
          return unless node.method_name == PARSE_METHOD
          return unless time_parse_receiver?(node.receiver)
          return if frozen_string_literal_argument?(node)
          return if surrounded_by_rescue?(node)

          add_offense(node, message: format(MSG, method: node.source))
        end

        private

        # Matches receivers: Time.zone, Time (const), DateTime.
        # Time.zone — (send (const nil :Time) :zone)
        # Time/DateTime — (const nil :Time), (const nil :DateTime)
        def time_parse_receiver?(receiver)
          return false unless receiver

          # Time.zone — receiver is (send (const nil :Time) :zone)
          if receiver.send_type? && receiver.method_name == :zone
            inner = receiver.receiver
            return true if inner&.const_type? && short_const_name(inner) == 'Time'
          end

          # Time or DateTime — receiver is (const nil :Time) or (const nil :DateTime)
          return true if receiver.const_type? && RECEIVER_NAMES.include?(short_const_name(receiver))

          false
        end

        # Extract the short const name: (const nil :Time) => "Time".
        def short_const_name(node)
          node.children[1].to_s
        end

        # Exclude calls where the sole argument is a frozen string literal
        # (e.g., Time.zone.parse("2025-01-01")). These are known parseable at
        # load time and cannot raise ArgumentError.
        def frozen_string_literal_argument?(node)
          args = node.arguments
          return false unless args.size == 1

          arg = args.first
          # Plain string literals (str nodes) are frozen; dstr (interpolated) are not.
          arg.str_type?
        end

        # Walk ancestors for a surrounding rescue node whose resbody catches
        # ArgumentError or StandardError.
        #
        # AST structure of a rescue:
        #   (rescue <body> <resbody> ... <else?>)
        # The parse call is a descendant of the rescue body (children[0]).
        # The resbody (children[1]) contains the exception types.
        def surrounded_by_rescue?(node)
          node.each_ancestor(:rescue).any? do |rescue_node|
            # The parse call must be inside the rescue body (children[0]),
            # not inside the resbody handler or else clause.
            body = rescue_node.children[0]
            next false unless body
            next false unless node_within?(node, body)

            # Check all resbody children for matching exception types.
            rescue_node.children[1...].each do |child|
              next unless child&.resbody_type?
              return true if catches_argument_error?(child)
            end

            false
          end
        end

        # Whether target is a descendant of (or equal to) root.
        def node_within?(target, root)
          return true if target.equal?(root)
          return true if root.each_node.any? { |n| n.equal?(target) }

          false
        end

        # Resbody children: [0] exception type(s), [1] variable binding, [2] body.
        # Bare rescue (no exception type in children[0]) catches StandardError.
        def catches_argument_error?(resbody)
          exception_types = resbody.children[0]
          # Bare rescue catches StandardError (superset of ArgumentError).
          return true if exception_types.nil?

          types = if exception_types.array_type?
                    exception_types.children
                  else
                    [exception_types]
                  end

          types.any? do |type_node|
            next false unless type_node&.const_type?

            name = full_const_name(type_node)
            %w[ArgumentError StandardError].include?(name)
          end
        end

        def full_const_name(node)
          return nil unless node&.const_type?

          parts = []
          current = node
          iterations = 0
          while current&.const_type?
            iterations += 1
            break if iterations > 1_000

            parts.unshift(current.children[1].to_s)
            current = current.children[0]
          end
          parts.join('::')
        end
      end
    end
  end
end
