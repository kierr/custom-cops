# typed: false # RuboCop cop — T is undefined at load time
# frozen_string_literal: true

module RuboCop
  module Cop
    module Sorbet
      # Detects `def initialize(**opts)` or `def initialize(options)` patterns in
      # classes that should use Sorbet-typed explicit keyword arguments instead.
      # Options splats and opaque options hashes bypass Sorbet's type checking —
      # the compiler cannot verify what keys are consumed or their types.
      #
      # Only flags `initialize` methods (constructors) where this pattern most
      # commonly undermines type safety. Regular methods using `**opts` for
      # forwarding are not flagged.
      #
      # @example
      #
      #   # bad — **opts bypasses type checking
      #   sig { void }
      #   def initialize(**opts)
      #     @name = opts[:name]
      #   end
      #
      #   # bad — opaque options hash
      #   sig { void }
      #   def initialize(options = {})
      #     @name = options[:name]
      #   end
      #
      #   # good — explicit keyword args with types
      #   sig { params(name: String).void }
      #   def initialize:)
      #     @name = name
      #   end
      #
      #   # good — T::Struct uses props macro, not initialize
      #   class MyStruct < T::Struct
      #     prop :name, String
      #   end
      class NoOptionsSplatInConstructor < Base
        MSG = 'Replace `%<pattern>s` with explicit keyword arguments. Options splats bypass Sorbet type checking.'

        def on_def(node)
          return unless node.method_name == :initialize

          args = node.arguments
          return if args.empty?

          offending_arg = args.find do |arg|
            arg.kwrestarg_type? ||
              ((arg.arg_type? || arg.optarg_type?) && options_param_name?(arg))
          end

          return unless offending_arg

          pattern = offending_arg.kwrestarg_type? ? '**opts' : 'options'
          add_offense(offending_arg, message: format(MSG, pattern:))
        end

        private

        # Check if a positional argument has a conventional "options" name.
        def options_param_name?(arg)
          %w[options opts settings config].include?(arg.name.to_s)
        end
      end
    end
  end
end
