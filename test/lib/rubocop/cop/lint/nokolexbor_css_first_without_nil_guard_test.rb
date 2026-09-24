# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

# Tests for Lint/NokolexborCssFirstWithoutNilGuard, which flags `.css(...).first`
# or `.css(...).last` without a subsequent nil guard on the result.
class NokolexborCssFirstWithoutNilGuardTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::NokolexborCssFirstWithoutNilGuard

  def test_flags_css_first_chained_without_guard
    assert_offense(COP, "doc.css('table').first.css('tr')")
  end

  def test_flags_css_last_chained_without_guard
    assert_offense(COP, "doc.css('table').last.css('tr')")
  end

  def test_flags_assigned_without_guard
    assert_offense(COP, <<~RUBY)
      table = doc.css('table').first
      table.css('tr')
    RUBY
  end

  # --- Good: no offenses ---

  def test_no_offense_with_nil_guard
    assert_no_offense(COP, <<~RUBY)
      table = doc.css('table').first
      return if table.nil?
      table.css('tr')
    RUBY
  end

  def test_no_offense_with_safe_navigation
    assert_no_offense(COP, "doc.css('table').first&.css('tr')")
  end

  def test_no_offense_with_compound_guard_nil_first
    assert_no_offense(COP, <<~RUBY)
      table = doc.css('table').first
      return if table.nil? || skip?
      table.css('tr')
    RUBY
  end

  def test_no_offense_with_compound_guard_nil_second
    # Regression: `return check_condition?` inside `any?` returned on the first
    # child, so a guard on the second branch was not recognized (false positive).
    assert_no_offense(COP, <<~RUBY)
      table = doc.css('table').first
      return if skip? || table.nil?
      table.css('tr')
    RUBY
  end

  def test_no_offense_for_at_css
    assert_no_offense(COP, "doc.at_css('table')")
  end

  def test_no_offense_for_first_with_argument
    assert_no_offense(COP, "doc.css('items').first(2)")
  end

  def test_no_offense_with_truthy_guard
    assert_no_offense(COP, <<~RUBY)
      table = doc.css('table').first
      return unless table
      table.css('tr')
    RUBY
  end
end
