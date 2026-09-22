# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `Date.new(year, month, day)` calls where any argument derives from
      # untrusted sources without guard clauses or rescue. `Date.new` raises
      # `ArgumentError` on out-of-range month/day values and `TypeError` on nil
      # arguments. Fixes in wi_courts_gov, age_calculation, and address_normalization
      # show this crash pattern repeats across the codebase.
      #
      # The cop flags `Date.new(...)` when any argument is a method call, hash access
      # (`[]`), or local variable sourced from a method parameter -- not a literal
      # integer. Calls already wrapped in a `rescue ArgumentError` (or broader) or
      # where `NumericUtil.safe_int` validates all dynamic inputs are excluded.
      # Date-component accessors (e.g., `today.year`, `date.month`) on Date/Time
      # receivers are trusted since they always return valid integers.
      #
      # @example
      #
      #   # bad -- year from method arg, no rescue
      #   def build_date(year)
      #     Date.new(year, 1, 1)
      #   end
      #
      #   # bad -- hash access without guard
      #   Date.new(params[:year], params[:month], params[:day])
      #
      #   # good -- all arguments are literal integers
      #   Date.new(2025, 1, 15)
      #
      #   # good -- date-component accessors produce valid integers
      #   Date.new(today.year, today.month, 1)
      #
      #   # good -- wrapped in rescue ArgumentError
      #   begin
      #     Date.new(year, month, day)
      #   rescue ArgumentError
      #     nil
      #   end
      #
      #   # good -- NumericUtil.safe_int guards inputs
      #   Date.new(NumericUtil.safe_int(year), NumericUtil.safe_int(month), 1)
      class DateNewWithUnguardedArguments < Base
        MSG = 'Guard `Date.new` arguments: wrap in `rescue ArgumentError` or validate with `NumericUtil.safe_int`.'

        # The only method name we care about.
        METHOD_NAME = :new

        # Const name for the Date receiver.
        DATE_CONST = 'Date'

        # Method calls that sanitize integer inputs, making them safe for Date.new.
        SANITIZER_RECEIVERS = %w[NumericUtil].freeze
        SANITIZER_METHODS = %i[safe_int].freeze

        # Node types considered potentially untrusted (not literal integers or const refs).
        DYNAMIC_NODE_TYPES = %i[send lvar ivar cvar gvar].freeze

        # Date/Time accessors that always return valid integers for Date.new arguments.
        DATE_COMPONENT_METHODS = %i[year month day mday wday yday].freeze

        def on_send(node)
          return unless node.method_name == METHOD_NAME
          return unless date_const_receiver?(node.receiver)
          return unless any_untrusted_argument?(node)
          return if all_dynamic_args_sanitized?(node)
          return if surrounded_by_rescue?(node)

          add_offense(node)
        end

        private

        # Matches receiver (const nil :Date).
        def date_const_receiver?(receiver)
          return false unless receiver
          return false unless receiver.const_type?

          short_const_name(receiver) == DATE_CONST
        end

        def short_const_name(node)
          node.children[1].to_s
        end

        # Whether any argument is non-literal (method call, hash access, lvar from params).
        def any_untrusted_argument?(node)
          node.arguments.any? do |arg|
            untrusted?(arg)
          end
        end

        # An argument is untrusted if it is not an integer literal, const reference,
        # trusted date-component accessor, or sanitized call.
        def untrusted?(node)
          return false if node.int_type?
          return false if node.const_type?
          return false if trusted_date_component?(node)
          return false if sanitized_call?(node)

          # Method calls (includes hash access via []), local variables, instance variables,
          # and global variables are all potentially untrusted.
          DYNAMIC_NODE_TYPES.include?(node.type)
        end

        # Recognizes safe date-component access like `today.year`, `date.month`,
        # `Time.current.year`, `Date.today.month`. These always return valid integers
        # because year/month/day accessors on any Date/Time/DateTime object produce
        # values in the correct range for Date.new.
        def trusted_date_component?(node)
          return false unless node.send_type?
          return false unless DATE_COMPONENT_METHODS.include?(node.method_name)

          # Any receiver is fine -- year/month/day only exist on temporal objects
          # and always return valid integers.
          node.receiver
        end

        # Check if ALL non-literal arguments are wrapped in NumericUtil.safe_int(...).
        def all_dynamic_args_sanitized?(node)
          dynamic_args = node.arguments.reject(&:int_type?)
          return false if dynamic_args.empty?

          dynamic_args.all? do |arg|
            sanitized_call?(arg)
          end
        end

        def sanitized_call?(node)
          return false unless node.send_type?

          return false unless SANITIZER_METHODS.include?(node.method_name)

          receiver = node.receiver
          return false unless receiver&.const_type?

          SANITIZER_RECEIVERS.include?(short_const_name(receiver))
        end

        # Walk ancestors for a surrounding rescue node whose resbody catches
        # ArgumentError, TypeError, or StandardError.
        def surrounded_by_rescue?(node)
          node.each_ancestor(:rescue).any? do |rescue_node|
            body = rescue_node.children[0]
            next false unless body
            next false unless node_within?(node, body)

            rescue_node.children[1...].each do |child|
              next unless child&.resbody_type?
              return true if catches_date_error?(child)
            end

            false
          end
        end

        def node_within?(target, root)
          return true if target.equal?(root)
          return true if root.each_node.any? { |n| n.equal?(target) }

          false
        end

        # Check if resbody catches ArgumentError, TypeError, or StandardError.
        # Bare rescue (no exception type) catches StandardError.
        def catches_date_error?(resbody)
          exception_types = resbody.children[0]
          return true if exception_types.nil?

          types = if exception_types.array_type?
                    exception_types.children
                  else
                    [exception_types]
                  end

          types.any? do |type_node|
            next false unless type_node&.const_type?

            name = full_const_name(type_node)
            %w[ArgumentError TypeError StandardError].include?(name)
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
