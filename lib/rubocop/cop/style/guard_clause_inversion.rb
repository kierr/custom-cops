# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # DECISION: this cop is disabled in config/default.yml and must not be enabled as-is.
      # Its premise is unsound. A `return unless X` guard returns when X is false, so
      # the statements after it run when X is TRUE — they are reachable, not
      # "unreachable" as the original message claimed. The flagged shape
      # (`return unless X; handle(X-true case)`) is idiomatic correct Ruby: guard out
      # the uninteresting case, then handle the case of interest. A full audit of all
      # 14 real-world offenses (#1198) found 0 real bugs and 14 false positives —
      # e.g. `return unless wait_thr.alive?` then kill+raise Timeout (the timeout
      # path), `return unless samesite == 'None' && !secure` then raise (the invalid
      # case), `return unless unresolved.positive?` then warn (the partial-DNS case).
      # No syntactic tightening recovers a sound target: even an unconditional `raise`
      # after the guard runs correctly on the X-true path. Would need a genuinely
      # different bug class (e.g. flow-sensitive detection of a guard inverted from
      # intent) to reconsider — left disabled as a stub for that rewrite.
      class GuardClauseInversion < Base
        MSG = 'Unreachable error-handling after guard clause. Use `if %<condition>s` instead of `return unless %<condition>s`.'

        # Methods that signal error-handling intent.
        ERROR_METHODS = %i[raise fail].freeze
        ERROR_LOG_METHODS = %i[error warn fatal].freeze

        # Matches `return unless condition` — parsed as (if condition nil (return)).
        # The true-branch is nil and the false-branch is a bare return.
        # NodePattern `nil` matches the nil node type, not Ruby nil, so we use
        # `_` and check the true-branch programmatically.
        def_node_matcher :return_in_else_branch?, <<~PATTERN
          (if $_ _ (return))
        PATTERN

        def on_if(node)
          condition = return_in_else_branch?(node)
          return unless condition
          return unless node.children[1].nil? # true-branch must be empty
          return unless followed_by_error_handling?(node)

          add_offense(node.loc.keyword, message: format(MSG, condition: condition.source))
        end

        private

        # The guard `if` node and the error-handling statements are siblings in
        # a `begin` block. Check subsequent siblings for error-handling calls.
        def followed_by_error_handling?(if_node)
          parent = if_node.parent
          return false unless parent&.begin_type?

          siblings = parent.children
          idx = siblings.index(if_node)
          return false unless idx

          siblings[(idx + 1)..].any? { |sibling| error_handling_node?(sibling) }
        end

        def error_handling_node?(node)
          return false unless node

          case node.type
          when :send
            ERROR_METHODS.include?(node.method_name) || error_log_call?(node)
          when :block
            # e.g., logger.error { "msg" }
            error_handling_node?(node.children.first)
          when :begin
            node.children.any? { |child| error_handling_node?(child) }
          else
            false
          end
        end

        def error_log_call?(node)
          return false unless node&.send_type?
          return false unless ERROR_LOG_METHODS.include?(node.method_name)

          receiver = node.receiver
          return false unless receiver

          # logger.error, @logger.error, etc.
          (receiver.send_type? && receiver.method_name == :logger) ||
            (receiver.ivar_type? && receiver.name == :@logger) ||
            (receiver.lvar_type? && receiver.name == :logger)
        end
      end
    end
  end
end
