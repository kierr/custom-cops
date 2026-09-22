# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Security
      # Detects `ServiceResult.failure(message: e.message)` or
      # `ServiceResult.failure(message: e)` where the raw exception message
      # could contain credentials, API keys, or internal paths. Exception
      # messages from external libraries and HTTP adapters routinely include
      # full URLs with query-string tokens, response bodies with secrets, and
      # filesystem paths. Passing these through as the user-facing message
      # leaks sensitive data.
      #
      # The fix: use a sanitized constant string for the message, and attach
      # the raw error via `error: e` for internal logging only.
      #
      # Scope restricted to `app/controllers/`, `app/consumers/`, and
      # `app/services/` to avoid flagging test factories and internal
      # infrastructure where the exception is under test control.
      #
      # TODO(error-handling.wire-disclosure-cop): this cop is implemented and
      # tested but not required in .rubocop.yml, so it enforces nothing. Wiring
      # it surfaces dozens of existing `message: "...#{e.message}"` sites across
      # app/services — a project-wide message-shape migration (tests assert exact
      # messages) that needs a decision on enablement + legacy-offense handling
      # (regenerating .rubocop_todo.yml) before the require line is added.
      # Until then ServiceResult.sanitize_message is the runtime safeguard.
      #
      # @example
      #
      #   # bad — raw exception message exposed to callers
      #   ServiceResult.failure(message: e.message, error: e)
      #   ServiceResult.failure(message: "Failed: #{e.message}")
      #   ServiceResult.failure(message: e)
      #
      #   # good — constant string for user-facing message, raw error for logging
      #   ServiceResult.failure(message: 'api_client.request_failed', error: e)
      #   ServiceResult.failure(message: 'Fetch failed', error: e)
      #
      #   # good — string interpolation that does not involve exception variables
      #   ServiceResult.failure(message: "Order #{order_id} not found")
      class ServiceResultErrorDisclosure < Base
        MSG = 'Avoid passing raw exception messages to `ServiceResult.failure` message: — ' \
              'they may contain credentials or internal paths. Use a constant string and ' \
              'attach the exception via `error:` for internal logging.'

        # Common rescue variable names for exception objects.
        EXCEPTION_VARIABLE_NAMES = %i[e ex error err exception exc].freeze

        def_node_matcher :service_result_failure?, <<~PATTERN
          (send (const {nil? (cbase)} :ServiceResult) :failure ...)
        PATTERN

        def on_send(node)
          return unless service_result_failure?(node)
          return unless in_scope?

          kwargs_hash = node.first_argument
          return unless kwargs_hash&.hash_type?

          kwargs_hash.each_pair do |key, value|
            next unless key.sym_type? && key.value == :message
            next unless exception_message_leak?(value)

            add_offense(value)
          end
        end

        private

        # Only flag files in controller, consumer, and service layers.
        # Paths may be relative (app/services/...) or absolute (/path/to/app/services/...).
        def in_scope?
          path = processed_source.file_path
          path.include?('app/controllers/') ||
            path.include?('app/consumers/') ||
            path.include?('app/services/')
        end

        # Matches when the message argument is:
        # 1. A bare exception variable: `message: e`
        # 2. A .message send on an exception variable: `message: e.message`
        # 3. A string interpolation containing an exception variable or
        #    its .message call: `message: "Failed: #{e.message}"`
        def exception_message_leak?(node)
          return false unless node

          return true if exception_variable?(node)
          return true if exception_message_send?(node)

          if node.dstr_type?
            return node.children.any? do |child|
              next false unless child.begin_type?

              # The begin node wraps the interpolated expression.
              child.children.any? { |expr| exception_leak_expression?(expr) }
            end
          end

          false
        end

        # Matches `e.message` where `e` is a known exception variable name.
        def exception_message_send?(node)
          return false unless node&.send_type?
          return false unless node.method_name == :message

          exception_variable?(node.receiver)
        end

        # Checks if a single interpolated expression is an exception leak:
        # - bare exception variable: `#{e}`
        # - .message call: `#{e.message}`
        # - .class + .message: `#{e.class}: #{e.message}` (compound interpolation)
        def exception_leak_expression?(node)
          return false unless node

          return true if exception_variable?(node)
          return true if exception_message_send?(node)

          # `e.class` also leaks — class names can reveal internal paths.
          return true if exception_class_send?(node)

          false
        end

        # Matches exception variables as lvar (rescue context) or bare send
        # (parsed without rescue context where `e` looks like a method call).
        def exception_variable?(node)
          return false unless node

          return EXCEPTION_VARIABLE_NAMES.include?(node.name) if node.lvar_type?

          return EXCEPTION_VARIABLE_NAMES.include?(node.method_name) if node.send_type? && node.receiver.nil?

          false
        end

        # Matches `e.class` where `e` is a known exception variable name.
        def exception_class_send?(node)
          return false unless node&.send_type?
          return false unless node.method_name == :class

          exception_variable?(node.receiver)
        end
      end
    end
  end
end
