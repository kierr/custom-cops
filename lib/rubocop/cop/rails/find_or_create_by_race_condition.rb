# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Detects `find_or_create_by` (race-prone: selects then inserts) and
      # recommends `create_or_find_by!` (atomic: inserts then catches
      # uniqueness violations). Also flags the manual equivalent
      # `find_by(...) || create!(...)` which has the same TOCTOU window.
      #
      # The bang version `find_or_create_by!` is excluded because it at least
      # raises on failure rather than silently returning nil.
      #
      # @example
      #
      #   # bad — TOCTOU race between SELECT and INSERT
      #   User.find_or_create_by(email: params[:email])
      #
      #   # bad — manual equivalent has the same race
      #   User.find_by(email: params[:email]) || User.create!(email: params[:email])
      #
      #   # good — bang version raises on failure
      #   User.find_or_create_by!(email: params[:email])
      #
      #   # good — atomic upsert pattern
      #   User.create_or_find_by!(email: params[:email])
      class FindOrCreateByRaceCondition < Base
        MSG = 'Use `create_or_find_by!` instead of `find_or_create_by` — the latter has a TOCTOU race between SELECT and INSERT.'

        MANUAL_PATTERN_MSG = 'Use `create_or_find_by!` instead of `find_by(...) || create!(...)` — the manual pattern has the same TOCTOU race.'

        # Matches `find_by(...)` followed by `|| create!(...)`.
        # Parsed as: (or (send _ :find_by ...) (send _ :create! ...))
        def_node_matcher :find_by_or_create?, <<~PATTERN
          (or
            (send _ :find_by ...)
            (send _ :create! ...))
        PATTERN

        def on_send(node)
          return unless node.method_name == :find_or_create_by

          add_offense(node.loc.selector, message: MSG)
        end

        def on_or(node)
          return unless find_by_or_create?(node)

          add_offense(node, message: MANUAL_PATTERN_MSG)
        end
      end
    end
  end
end
