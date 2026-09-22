# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `insert_all(unique_by:)` where the intent is likely upsert
      # behavior. `insert_all` with `unique_by` triggers ON CONFLICT DO NOTHING
      # — silently skipping duplicates instead of updating existing rows. When
      # the caller passes `unique_by`, they expect conflict handling, but
      # insert_all discards the new data rather than merging it. Use
      # `upsert_all` for actual upsert semantics (ON CONFLICT DO UPDATE).
      #
      # @example
      #
      #   # bad — unique_by implies upsert intent, but insert_all silently skips
      #   Person::Entity.insert_all(rows, unique_by: :uuid)
      #
      #   # good — upsert_all updates existing rows on conflict
      #   Person::Entity.upsert_all(rows, unique_by: :uuid)
      #
      #   # good — insert_all without unique_by is a genuine bulk insert
      #   Person::Entity.insert_all(rows)
      class InsertAllNotUpsertAll < Base
        MSG = 'Use `upsert_all` instead of `insert_all` with `unique_by:`. ' \
              '`insert_all` does ON CONFLICT DO NOTHING — silently skipping duplicates instead of updating.'

        # Matcher for insert_all calls with a unique_by keyword argument.
        def_node_matcher :insert_all_with_unique_by?, <<~PATTERN
          (send _ :insert_all ... (hash <(pair (sym :unique_by) _) ...>))
        PATTERN

        def on_send(node)
          return unless insert_all_with_unique_by?(node)

          # No autocorrect: insert_all→upsert_all flips ON CONFLICT DO NOTHING
          # to DO UPDATE, rewriting existing rows. DO NOTHING dedup is an
          # intentional Rails pattern, and whether the caller wanted skip-vs-
          # overwrite is not inferable from the call. Cop is disabled by
          # default (see .rubocop.yml) — detection alone over-flags the
          # legitimate DO NOTHING pattern.
          add_offense(node.loc.selector)
        end
      end
    end
  end
end
