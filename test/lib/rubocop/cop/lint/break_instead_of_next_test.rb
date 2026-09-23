# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class BreakInsteadOfNextTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::BreakInsteadOfNext

  # --- Bad: offenses expected ---

  def test_flags_break_if_present_in_each
    offenses = investigate(COP, <<~RUBY)
      results.each do |batch|
        non_existing = find_missing(batch)
        break if non_existing.present?
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/next/, offenses.first.message)
  end

  OFFENSE_CASES = {
    'break_if_any' => "items.each do |item|\n  break if item.errors.any?\nend",
    'break_if_exist' => "records.each do |r|\n  break if duplicate.exist?\nend",
    'break_if_exists' => "records.each do |r|\n  break if duplicate.exists?\nend",
    'break_in_map_with_present' => "items.map do |item|\n  break if item.invalid.present?\n  transform(item)\nend",
    'break_in_select_with_any' => "items.select do |item|\n  break if item.errors.any?\n  item.valid?\nend",
    'break_if_negated_blank' => "items.each do |item|\n  break if !item.name.blank?\nend",
    'break_if_negated_empty' => "items.each do |item|\n  break if !item.list.empty?\nend",
    'break_if_negated_nil' => "items.each do |item|\n  break if !item.value.nil?\nend"
  }.freeze

  OFFENSE_CASES.each do |name, source|
    define_method(:"test_flags_#{name}") do
      offenses = investigate(COP, source)

      assert_equal 1, offenses.size
    end
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'next_if_present' => "results.each do |batch|\n  next if batch.present?\nend",
    'break_without_presence_check' => "results.each do |batch|\n  break if batch == :stop\nend",
    'break_in_loop' => "loop do\n  break if done?\nend",
    'break_in_while' => "while running?\n  break if cancelled?\n  tick\nend",
    'break_in_for' => "for item in items\n  break if item.nil?\n  process(item)\nend",
    'break_if_present_in_find' => "items.find do |item|\n  break if item.expired.present?\n  item.match?\nend"
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses, "Expected no offense for #{name}"
    end
  end
end
