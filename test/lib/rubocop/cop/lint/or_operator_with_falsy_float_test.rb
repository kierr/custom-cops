# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class OrOperatorWithFalsyFloatTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::OrOperatorWithFalsyFloat

  # NOTE: This cop is DISABLED in .rubocop.yml because its premise is wrong
  # (0.0 is truthy in Ruby). Additionally, `def extract_name` is nested inside
  # `def numeric_named?`, causing a NoMethodError on first call — the
  # Commissioner silently catches the error, producing zero offenses. These
  # tests document actual behavior: the cop never fires.

  def test_no_offense_for_or_with_float
    # The cop crashes silently on first invocation due to nested method def bug.
    offenses = investigate(COP, <<~RUBY)
      score || 0.0
    RUBY

    assert_empty offenses
  end

  def test_no_offense_for_or_with_integer
    offenses = investigate(COP, <<~RUBY)
      amount || 0
    RUBY

    assert_empty offenses
  end

  # Non-numeric names are correctly excluded (no crash needed)
  def test_no_offense_for_non_numeric_name
    offenses = investigate(COP, <<~RUBY)
      name || "default"
    RUBY

    assert_empty offenses
  end
end
