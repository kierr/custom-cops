# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class NoSystemTimeNowTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Time::NoSystemTimeNow

  # --- Bad: offenses expected ---

  def test_flags_time_now
    offenses = investigate(COP, <<~RUBY)
      Time.now
    RUBY

    assert_equal 1, offenses.size
    assert_match(/system clock/, offenses.first.message)
  end

  OFFENSE_CASES = {
    'date_today' => 'Date.today',
    'date_time_now' => 'DateTime.now',
    'fully_qualified_time_now' => '::Time.now',
    'fully_qualified_date_today' => '::Date.today'
  }.freeze

  OFFENSE_CASES.each do |name, source|
    define_method(:"test_flags_#{name}") do
      offenses = investigate(COP, source)

      assert_equal 1, offenses.size, "Expected offense for #{name}"
    end
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'time_current' => 'Time.current',
    'time_zone_now' => 'Time.zone.now',
    'date_current' => 'Date.current',
    'time_parse' => "Time.parse('2025-01-01')",
    'other_now_call' => 'Clock.now'
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses, "Expected no offense for #{name}"
    end
  end
end
