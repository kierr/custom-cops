# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Sorbet
      # Detects duplicate consecutive `sig` blocks before a method definition.
      # When two `sig` blocks appear before a `def`, the second overrides the first,
      # but the stale first sig causes confusion and may produce wrong RBI output.
      #
      # @example
      #
      #   # bad — stale first sig is overridden
      #   sig { returns(T.any(ServiceResult[T.untyped], T::Hash[Symbol, T.untyped])) }
      #   sig { params(mapped: T::Hash).returns(T.nilable(ServiceResult[T.untyped])) }
      #   def validate_evidence(mapped)
      #
      #   # good — single sig before def
      #   sig { params(mapped: T::Hash).returns(T.nilable(ServiceResult[T.untyped])) }
      #   def validate_evidence(mapped)
      class DuplicateSig < Base
        extend AutoCorrector

        MSG = 'Remove stale `sig` block — only the last `sig` before `def` takes effect.'

        def_node_matcher :sig_block?, <<~PATTERN
          (block (send nil? :sig) ...)
        PATTERN

        def on_def(node)
          sigs = consecutive_sigs_before(node)
          return unless sigs.size > 1

          sigs[0..-2].each do |stale_sig|
            add_offense(stale_sig) do |corrector|
              src = stale_sig.source_range
              line_range = src.with(begin_pos: src.begin_pos - src.column, end_pos: src.end_pos + 1)
              corrector.remove(line_range)
            end
          end
        end

        def on_defs(node)
          on_def(node)
        end

        private

        def consecutive_sigs_before(def_node)
          parent = def_node.parent
          return [] unless parent&.begin_type?

          siblings = parent.children
          idx = siblings.index(def_node)
          return [] unless idx&.positive?

          sigs = []
          siblings[0...idx].reverse_each do |sib|
            break unless sig_block?(sib)

            sigs.unshift(sib)
          end
          sigs
        end
      end
    end
  end
end
