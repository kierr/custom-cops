# typed: ignore
# frozen_string_literal: true

# Tests for Lint/ArrayShiftBeforeMatchCheck, which flags `shift` chained with
# a match/check followed by a conditional return that discards the shifted element.
require_relative '../../../../test_helper'

class ArrayShiftBeforeMatchCheckTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::ArrayShiftBeforeMatchCheck

  def test_flags_shift_safe_nav_chained_match_then_return_unless
    offenses = investigate(COP, <<~RUBY)
      match = lines.shift&.match(REGEX)
      return unless match
    RUBY

    assert_equal 1, offenses.size
    assert_match(/shift.*conditional return/, offenses.first.message)
  end

  def test_flags_shift_regular_chained_match_then_return_unless
    offenses = investigate(COP, <<~RUBY)
      match = lines.shift.match(REGEX)
      return unless match
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_return_if_form
    offenses = investigate(COP, <<~RUBY)
      match = lines.shift&.match(REGEX)
      return if match
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_return_if_negated_form
    offenses = investigate(COP, <<~RUBY)
      match = lines.shift&.match(REGEX)
      return if !match
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'check_first_then_shift' => <<~RUBY,
      line = lines.first
      match = line&.match(REGEX)
      return unless match
      lines.shift
    RUBY
    'shift_used_regardless_of_match' => <<~RUBY,
      first_line = lines.shift
      process(first_line)
    RUBY
    'shift_without_conditional_return' => <<~RUBY,
      header = lines.shift
      log("Skipped header: \#{header}")
    RUBY
    'conditional_return_references_different_var' => <<~RUBY
      match = lines.shift&.match(REGEX)
      return unless other_match
    RUBY
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      assert_no_offense(COP, source)
    end
  end
end
