# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects global variable references (`$variable`) in application code.
      # Global variables bypass typed boundaries and create hidden coupling.
      # Use proper dependency injection with typed parameters instead.
      #
      # Allowed globals: $stdin, $stdout, $stderr, $LOAD_PATH, $LOADED_FEATURES,
      # $PROGRAM_NAME, $!, $@, $?, $~, $&, $`, $', $+, $_.
      #
      # @example
      #
      #   # bad
      #   DEFAULT_MANAGER = T.let($session_manager, T.untyped)
      #
      #   # good
      #   @manager = T.let(manager, T.nilable(SessionManager))
      #   manager || SessionManager.new
      class GlobalVariableFallback < Base
        MSG = 'Avoid global variables in application code. Use dependency injection with typed parameters.'

        ALLOWED_GLOBALS = %i[$stdin $stdout $stderr $LOAD_PATH $LOADED_FEATURES $PROGRAM_NAME $! $@ $? $~ $& $` $' $+
                             $_].freeze

        def on_gvar(node)
          return if ALLOWED_GLOBALS.include?(node.name)

          add_offense(node)
        end
      end
    end
  end
end
