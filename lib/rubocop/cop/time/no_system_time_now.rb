# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Time
      class NoSystemTimeNow < Base
        MSG = 'Avoid system clock helpers like `Time.now`, `Date.today`, and `DateTime.now` in app/lib. Prefer Rails time-zone aware helpers.'

        def_node_matcher :time_now?, <<~PATTERN
          (send (const {nil? (cbase)} :Time) :now)
        PATTERN

        def_node_matcher :date_today?, <<~PATTERN
          (send (const {nil? (cbase)} :Date) :today)
        PATTERN

        def_node_matcher :date_time_now?, <<~PATTERN
          (send (const {nil? (cbase)} :DateTime) :now)
        PATTERN

        def on_send(node)
          return unless time_now?(node) || date_today?(node) || date_time_now?(node)

          add_offense(node)
        end
      end
    end
  end
end
