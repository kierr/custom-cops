# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # Detects a Hash literal returned (or ending a branch) inside a method body
      # where the hash contains only static keys and values. Every call to such a
      # method allocates a new Hash with identical contents — it should be extracted
      # to a frozen constant instead.
      #
      # Only pure-literal hashes are flagged: symbol, string, integer, float, and
      # boolean keys and values. Hashes referencing local variables, method calls,
      # or ivars are not flagged because their contents may vary per call.
      #
      # @example
      #
      #   # bad
      #   def status_codes
      #     { pending: 1, active: 2 }
      #   end
      #
      #   # good
      #   STATUS_CODES = { pending: 1, active: 2 }.freeze
      #
      #   def status_codes
      #     STATUS_CODES
      #   end
      class HashBuiltEveryCall < Base
        MSG = 'Extract this Hash literal to a frozen constant. It returns the same value on every call and should not be allocated repeatedly.'

        # Match a def whose body is a bare hash literal (implicit return).
        def_node_matcher :def_returning_hash?, <<~PATTERN
          {(def _ _ (hash ...))
           (defs _ _ _ (hash ...))}
        PATTERN

        # Match a def whose body is a begin-block ending with a hash literal.
        def_node_matcher :def_ending_in_hash?, <<~PATTERN
          {(def _ _ (begin ... (hash ...)))
           (defs _ _ _ (begin ... (hash ...)))}
        PATTERN

        # Match a def whose body is an if/unless with hash literals in branches.
        def_node_matcher :def_with_branch_hash?, <<~PATTERN
          {(def _ _ {(if _ (hash ...) ...)
                      (if _ ... (hash ...))
                      (if _ (hash ...) (hash ...))})
           (defs _ _ _ {(if _ (hash ...) ...)
                        (if _ ... (hash ...))
                        (if _ (hash ...) (hash ...))})}
        PATTERN

        def on_def(node)
          _ = check_def(node)
        end

        def on_defs(node)
          _ = check_def(node)
        end

        private

        def check_def(node)
          # Node body: for `def foo; ...; end`, body is the expression after args.
          # For singleton defs, body is the last child.
          body = node.children[2..].last
          return unless body

          hashes = extract_candidate_hashes(body)
          return if hashes.empty?

          hashes.each do |hash_node|
            next unless pure_literal_hash?(hash_node)

            add_offense(hash_node, message: MSG)
          end
        end

        # Collect hash literals that are the "result" of the method body:
        # - The body itself (implicit return)
        # - The last child of a begin-block (implicit return)
        # - Branch bodies of an if/unless (conditional return)
        def extract_candidate_hashes(body)
          if body.hash_type?
            [body]
          elsif body.begin_type? && body.children.last&.hash_type?
            [body.children.last]
          elsif body.if_type?
            branches = [body.children[1], body.children[2]].compact
            branches.select(&:hash_type?)
          else
            []
          end
        end

        # A hash is "pure literal" when every key and every value is a static literal.
        # Symbol, string, integer, float, true, false, nil are allowed.
        # References to local variables, ivars, method calls, or constants that
        # might be mutable are excluded.
        def pure_literal_hash?(hash_node)
          return false unless hash_node.hash_type?
          return true if hash_node.children.empty? # empty hash `{}` is still wasteful

          hash_node.children.all? do |pair|
            next false unless pair.pair_type?

            literal_node?(pair.key) && literal_node?(pair.value)
          end
        end

        def literal_node?(node)
          node.sym_type? || node.str_type? || node.int_type? ||
            node.float_type? || node.true_type? || node.false_type? ||
            node.nil_type?
        end
      end
    end
  end
end
