# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects deterministic exponential backoff without random jitter.
      # Pure deterministic backoff causes thundering herd when multiple workers
      # retry simultaneously — all compute the same delay and request the downstream
      # service at the same instant.
      #
      # Matches methods/variables named backoff, retry_delay, delay, or wait that
      # compute a numeric value using multiplication or exponentiation, then checks
      # whether the enclosing method or assignment context includes a call to rand,
      # jitter, random, or SecureRandom. Flagged code lacks any randomization.
      #
      # Cannot safely autocorrect — the jitter formula varies by use case.
      # Consider `base * (2 ** attempt) * (0.5 + rand * 0.5)` or similar.
      #
      # @example
      #
      #   # bad — deterministic exponential backoff
      #   delay = base * (2 ** attempt)
      #   backoff = backoff * 2
      #   delay = 2 ** attempt
      #
      #   # good — includes jitter
      #   delay = base * (2 ** attempt) * (0.5 + rand * 0.5)
      #   backoff = backoff * 2 * rand
      #   delay = (2 ** attempt) + rand(1.0)
      #
      #   # good — delegation to a library that adds jitter internally
      #   Retriable.with_retry { do_work }
      class BackoffWithoutJitter < Base
        MSG = 'Deterministic backoff without jitter causes thundering herd. Add randomization, e.g. `base * (2 ** attempt) * (0.5 + rand * 0.5)`.'

        # Method/variable names that signal a backoff or retry delay computation.
        BACKOFF_NAMES = %i[backoff backoff_delay retry_delay delay wait wait_time retry_wait sleep_time retry_interval].freeze

        # Method calls that indicate randomization is present.
        JITTER_METHODS = %i[rand jitter random secure_random].freeze

        # Arithmetic operators that scale a delay value.
        SCALING_OPERATORS = %i[* **].freeze

        # Node types whose children should be traversed uniformly.
        # Assignment types (lvasgn, ivasgn, casgn) excluded — their first child
        # is a raw Symbol (variable name), not an AST node, which would crash
        # the recursive traversal.
        TRAVERSE_TYPES = %i[begin kwbegin block if and or array return].freeze

        def on_lvasgn(node)
          _ = check_assignment(node, node.name)
        end

        def on_ivasgn(node)
          _ = check_assignment(node, node.name.to_s.delete_prefix('@').to_sym)
        end

        def on_def(node)
          return unless BACKOFF_NAMES.include?(node.method_name)
          return if rationale?(node)

          body = node.body
          return unless body
          return unless contains_scaling?(body)
          return if tree_has_jitter?(body)

          add_offense(node.loc.name)

          private

          def check_assignment(node, name)
            return unless BACKOFF_NAMES.include?(name)
            return if rationale?(node)

            rhs = node.children[1]
            return unless rhs
            return unless contains_scaling?(rhs)
            return if context_has_jitter?(node)

            add_offense(node.loc.name)
          end

          # Per-instance exemption: a RATIONALE comment within 5 lines above
          # the assignment or def suppresses the offense. Legitimate when the
          # backoff runs under a single worker (no thundering herd possible) or
          # jitter is added by a caller the cop cannot see.
          def rationale?(node)
            return false unless node.loc.expression

            node_line = node.loc.expression.line
            processed_source.comments.any? do |comment|
              comment_line = comment.loc.expression.line
              comment_line >= node_line - 5 && comment_line < node_line &&
                comment.text.include?('RATIONALE')
            end
          end

          # Returns true if the expression tree contains multiplication or
          # exponentiation — the signature of exponential/linear backoff scaling.
          def contains_scaling?(node)
            return false unless node

            return scaling_send?(node) if node.send_type?
            return node.children.any? { |c| contains_scaling?(c) } if traverse_type?(node)

            false
          end

          def scaling_send?(node)
            return true if SCALING_OPERATORS.include?(node.method_name) && node.receiver

            node.arguments.any? { |a| contains_scaling?(a) } ||
              contains_scaling?(node.receiver)
          end

          # For assignment nodes, check for jitter in the rhs expression itself, the
          # enclosing method/block body, or a parent begin block (sibling statements).
          def context_has_jitter?(node)
            rhs = node.children[1]
            return true if rhs && tree_has_jitter?(rhs)

            ancestor = find_enclosing_method_or_block(node)
            if ancestor
              body = ancestor.type == :def ? ancestor.body : ancestor.children[2]
              return true if body && tree_has_jitter?(body)
            end

            # Check sibling statements in a begin block (e.g., backoff assignment
            # followed by a jittered computation on the next line).
            begin_body = find_enclosing_begin_body(node)
            begin_body && tree_has_jitter?(begin_body)
          end

          # Walks up to find a begin/kwbegin parent and returns its full body.
          def find_enclosing_begin_body(node)
            current = node.parent
            while current
              return current if %i[begin kwbegin].include?(current.type)
              break if %i[def defs block].include?(current.type)

              current = current.parent
            end
            nil
          end

          # Returns true if the node tree contains a rand/jitter/random/secure_random call.
          def tree_has_jitter?(node)
            return false unless node
            return false unless node.is_a?(RuboCop::AST::Node)

            return jitter_send?(node) if node.send_type?
            return assignment_rhs_has_jitter?(node) if %i[lvasgn ivasgn casgn].include?(node.type)
            return node.children.any? { |c| tree_has_jitter?(c) } if traverse_type?(node)

            false
          end

          # For assignment nodes, only check the RHS (children[1]) — the name
          # child is a raw Symbol, not an AST node.
          def assignment_rhs_has_jitter?(node)
            rhs = node.children[1]
            rhs ? tree_has_jitter?(rhs) : false
          end

          def jitter_send?(node)
            return true if JITTER_METHODS.include?(node.method_name)
            return true if secure_random_receiver?(node.receiver)

            tree_has_jitter?(node.receiver) ||
              node.arguments.any? { |a| tree_has_jitter?(a) }
          end

          def secure_random_receiver?(receiver)
            return false unless receiver

            (receiver.send_type? && receiver.method_name == :secure_random) ||
              (receiver.const_type? && receiver.source.include?('SecureRandom'))
          end

          def traverse_type?(node)
            TRAVERSE_TYPES.include?(node.type)
          end

          def find_enclosing_method_or_block(node)
            current = node.parent
            while current
              return current if %i[def defs block].include?(current.type)

              current = current.parent
            end
            nil
          end
        end
      end
    end
  end
end
