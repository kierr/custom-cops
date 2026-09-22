# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Logging
      # Detects logging (error/warn/fatal) immediately before a raise with a message.
      # The raise message carries the same information; error handlers and exception
      # backtraces provide the logging. Structured logging before bare `raise` (re-raise)
      # is not flagged — it adds context the original exception lacks.
      #
      # Simple string-only log calls are auto-corrected (removed). Structured log calls
      # with keyword arguments are flagged but not auto-corrected — the structured fields
      # may need to be preserved via exception context or a wrapping error class instead.
      #
      # @example
      #   # bad (auto-corrected)
      #   logger.error "IP #{ip} is banned."
      #   raise StandardError, "Banned IP #{ip}"
      #
      #   # bad (flagged, not auto-corrected — structured fields would be lost)
      #   logger.error('sync.failed', account_id: account.id, external_id: external_id)
      #   raise ArgumentError, "Invalid external_id '#{external_id}'"
      #
      #   # good — bare raise re-raises with structured context the exception lacks
      #   logger.error('batch_failed', message: result.message)
      #   raise
      class LogThenRaise < Base
        extend AutoCorrector

        MSG = 'Avoid logging before raise with a message — the exception carries the same information and will be logged by error handlers.'

        def_node_matcher :logging_call?, <<~PATTERN
          (send {(send nil? :logger) (ivar :@logger)} {:error :warn :fatal} ...)
        PATTERN

        # Matches log calls with a single string/interpolated-string argument (no structured fields).
        def_node_matcher :simple_log_call?, <<~PATTERN
          (send {(send nil? :logger) (ivar :@logger)} {:error :warn :fatal} {(str ...) (dstr ...)})
        PATTERN

        def on_send(node)
          return unless logging_call?(node)
          return unless (next_node = consecutive_sibling(node))
          return unless raise_with_string_message?(next_node)

          if simple_log_call?(node)
            add_offense(node) do |corrector|
              src = node.source_range
              # Extend range to include the preceding indentation and trailing newline
              line_range = src.with(
                begin_pos: src.begin_pos - src.column,
                end_pos: src.end_pos + 1 # trailing newline
              )
              corrector.remove(line_range)
            end
          else
            add_offense(node)
          end
        end

        private

        def consecutive_sibling(node)
          parent = node.parent
          return nil unless parent&.begin_type?

          siblings = parent.children
          idx = siblings.index(node)
          return nil unless idx && idx < siblings.size - 1

          siblings[(idx + 1)..].find { |s| !s.nil? }
        end

        def raise_with_string_message?(node)
          return false unless node&.send_type? && node.method_name == :raise

          node.arguments.any? { |arg| arg.str_type? || arg.dstr_type? }
        end
      end
    end
  end
end
