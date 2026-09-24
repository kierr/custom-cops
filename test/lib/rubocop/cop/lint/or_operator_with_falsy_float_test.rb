# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

# Tests for Lint/OrOperatorWithFalsyFloat.
#
# The cop's premise is factually wrong: Ruby `||` treats only nil and false as
# falsy, so `0.0 || 1.0 #=> 0.0`. The cop is DISABLED in config/default.yml
# because every offense is a false positive and the autocorrect is a semantic
# no-op for numeric values. These tests assert the disabled state so that
# re-enabling it is a visible, deliberate decision, not a silent regression.
class OrOperatorWithFalsyFloatTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::OrOperatorWithFalsyFloat

  # The cop is disabled in config/default.yml, so no source should produce
  # offenses regardless of whether the pattern matches the (buggy) matcher.
  def test_disabled_no_offense_for_or_with_float
    assert_no_offense(COP, <<~RUBY)
      score || 0.0
    RUBY
  end

  def test_disabled_no_offense_for_or_with_integer
    assert_no_offense(COP, <<~RUBY)
      amount || 0
    RUBY
  end

  def test_disabled_no_offense_for_non_numeric_name
    assert_no_offense(COP, <<~RUBY)
      name || "default"
    RUBY
  end

  # Even if enabled, string fallback and `&&` are not in the cop's target
  # pattern, so they remain no-offense under either state.
  def test_no_offense_for_string_fallback_even_if_enabled
    assert_no_offense(COP, <<~RUBY)
      name || "default"
    RUBY
  end

  def test_no_offense_for_and_operator
    assert_no_offense(COP, <<~RUBY)
      score && 0.0
    RUBY
  end
end
