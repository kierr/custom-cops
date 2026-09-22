# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `ensure` blocks where the last expression implicitly returns a
      # non-nil value, which masks any exception raised in the begin block.
      #
      # In Ruby, if an `ensure` block's last expression evaluates to a value,
      # that value replaces the return value of the entire begin/rescue/ensure
      # — including replacing a propagating exception. The exception is silently
      # discarded.
      #
      # Only flags ensure blocks with multiple statements where the last
      # expression is a value-returning call or read (not cleanup, nil, or
      # control flow). Single-statement ensure bodies are normal cleanup
      # patterns and are not flagged.
      #
      # Side-effect cleanup methods (close, unlink, disconnect, etc.) are
      # excluded because their return value is irrelevant — the intent is the
      # side effect, not the return value. The dangerous pattern is a
      # value-computing method or variable read that accidentally becomes the
      # ensure block's implicit return.
      #
      # This is a generalization of ConsumerEnsureSwallowsException for
      # non-consumer code. That cop checks for explicit `return` in consumer
      # ensure blocks; this cop checks for implicit non-nil return values in
      # any ensure block.
      #
      # @example
      #
      #   # bad — method call after cleanup masks exception
      #   def fetch
      #     do_work
      #   ensure
      #     cleanup
      #     calculate_expires_in
      #   end
      #
      #   # bad — variable read after cleanup masks exception
      #   def process
      #     do_work
      #   ensure
      #     cleanup
      #     @result
      #   end
      #
      #   # good — nil does not mask exceptions
      #   def fetch
      #     do_work
      #   ensure
      #     cleanup
      #     nil
      #   end
      #
      #   # good — raise in ensure propagates
      #   def fetch
      #     do_work
      #   ensure
      #     cleanup
      #     raise if $!
      #   end
      #
      #   # good — single cleanup call is normal ensure pattern
      #   def fetch
      #     do_work
      #   ensure
      #     cleanup
      #   end
      #
      #   # good — side-effect cleanup methods are excluded
      #   def fetch
      #     do_work
      #   ensure
      #     tempfile.close
      #     tempfile.unlink
      #   end
      class EnsureReturnMasksException < Base
        MSG = 'Last expression in `ensure` implicitly returns a value, which masks any in-flight exception. Add `nil` as the last expression.'

        # Methods that propagate or transfer control rather than returning a value.
        CONTROL_FLOW_METHODS = %i[raise throw fail].freeze

        # Control flow keywords that propagate or transfer.
        CONTROL_FLOW_TYPES = %i[return next break].freeze

        # Node types whose last expression never masks an exception.
        SAFE_LAST_TYPES = %i[nil].freeze

        # Side-effect cleanup methods whose return value is irrelevant.
        # These are common in ensure blocks for resource teardown.
        CLEANUP_METHODS = %i[
          close closed? disconnect shutdown unlink delete remove
          wait wait_for wait_for_termination join kill flush clear run stop exit
          finish terminate abandon reset free destroy
        ].freeze

        def on_ensure(node)
          body = ensure_body(node)
          return unless body

          # Only flag multi-statement ensure blocks. Single-expression ensure
          # bodies are normal cleanup patterns — the method call's return value
          # is the standard Ruby ensure idiom.
          statements = extract_statements(body)
          return unless statements.size > 1

          last_expr = statements.last
          return unless last_expr

          return if safe_last_expression?(last_expr)

          add_offense(last_expr, message: MSG)
        end

        private

        # Returns the body of an ensure node (the code after `ensure`).
        # Ensure structure: (ensure <begin-body> <ensure-body>).
        def ensure_body(ensure_node)
          ensure_node.children[1]
        end

        # Extracts statements from a node. For begin/kwbegin blocks,
        # returns the children. For single-expression bodies, wraps
        # in a single-element array.
        def extract_statements(node)
          case node.type
          when :begin, :kwbegin
            node.children
          else
            [node]
          end
        end

        # Determines whether the last expression is safe — it will not mask
        # a propagating exception.
        def safe_last_expression?(node)
          return true if SAFE_LAST_TYPES.include?(node.type)
          return true if CONTROL_FLOW_TYPES.include?(node.type)
          return true if control_flow_call?(node)
          return true if control_flow_if?(node)
          return true if assignment_type?(node)
          return true if cleanup_call?(node)
          return true if cleanup_if?(node)
          return true if safe_or_and?(node)

          false
        end

        # Checks if a node is a regular send or safe-navigation (csend) call.
        def any_send?(node)
          node.send_type? || node.csend_type?
        end

        # Checks if a send/csend node is a control flow method (raise, throw, fail).
        def control_flow_call?(node)
          return false unless any_send?(node)

          CONTROL_FLOW_METHODS.include?(node.method_name)
        end

        # Checks if a send/csend node is a side-effect cleanup method.
        # Handles both regular calls (pool.kill) and safe-navigation
        # (pool&.kill).
        def cleanup_call?(node)
          return false unless any_send?(node)

          CLEANUP_METHODS.include?(node.method_name)
        end

        # Checks if an `or` or `and` node has safe cleanup on both sides.
        # Handles patterns like `pool.wait || pool.kill` where both branches
        # are cleanup calls.
        def safe_or_and?(node)
          return false unless node.or_type? || node.and_type?

          left = node.children[0]
          right = node.children[1]

          safe_branch?(left) && safe_branch?(right)
        end

        # Checks if an if node's last evaluated expression is always safe.
        # Handles patterns like `raise if $!` (control flow) and
        # `if defined?(Metrics)` (conditional cleanup/metric recording).
        def control_flow_if?(node)
          return false unless node.if_type?

          true_branch = node.children[1]
          false_branch = node.children[2]

          true_is_control = true_branch && control_flow_call?(true_branch)
          false_is_nil_or_control = false_branch.nil? || safe_last_expression?(false_branch)

          true_is_control && false_is_nil_or_control
        end

        # Checks if an if node represents conditional cleanup or
        # conditional metric/logging — common ensure patterns where
        # the return value is irrelevant.
        def cleanup_if?(node)
          return false unless node.if_type?

          # `if defined?(X)` patterns — conditional feature checks
          condition = node.children[0]
          return true if defined_check?(condition)

          # Both branches contain cleanup or safe expressions
          true_branch = node.children[1]
          false_branch = node.children[2]

          true_safe = true_branch.nil? || safe_branch?(true_branch)
          false_safe = false_branch.nil? || safe_branch?(false_branch)

          true_safe && false_safe
        end

        # Checks if a node is a `defined?` check.
        def defined_check?(node)
          return true if node_defined_type?(node)

          # `defined?(X).nil?` or similar
          return false unless node.send_type?

          receiver = node.receiver
          receiver && node_defined_type?(receiver)
        end

        # Checks if a branch contains only safe expressions (cleanup,
        # assignments, nil, control flow, or nested safe structures).
        def safe_branch?(node)
          return true if node.nil?
          return true if SAFE_LAST_TYPES.include?(node.type)

          case node.type
          when :send, :csend
            cleanup_call?(node) || control_flow_call?(node)
          when :begin, :kwbegin
            node.children.all? { |child| safe_branch?(child) }
          when :if
            cleanup_if?(node) || control_flow_if?(node)
          when :or, :and
            safe_or_and?(node)
          else
            assignment_type?(node)
          end
        end

        # Node type check for :defined — avoids calling a potentially
        # unsupported `defined_type?` method.
        def node_defined_type?(node)
          node.type == :defined?
        end

        # Checks if a node is any form of assignment.
        def assignment_type?(node)
          node.type in :lvasgn | :ivasgn | :cvasgn | :gvasgn | :casgn | :op_asgn | :or_asgn | :and_asgn
        end
      end
    end
  end
end
