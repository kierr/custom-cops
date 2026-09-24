# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

# Tests for Lint/NilChainingWithoutGuard, which flags chained `[]` access on a
# variable assigned from a method call without a preceding nil guard.
class NilChainingWithoutGuardTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::NilChainingWithoutGuard

  def test_flags_chained_access_without_guard
    assert_offense(COP, <<~RUBY)
      def foo
        obj = event["actionable"]
        obj["nested"]
      end
    RUBY
  end

  # --- Good: no offenses (guards recognized) ---

  def test_no_offense_with_nil_guard
    assert_no_offense(COP, <<~RUBY)
      def foo
        obj = event["actionable"]
        return if obj.nil?
        obj["nested"]
      end
    RUBY
  end

  def test_no_offense_with_blank_guard
    assert_no_offense(COP, <<~RUBY)
      def foo
        obj = event["actionable"]
        return if obj.blank?
        obj["nested"]
      end
    RUBY
  end

  def test_no_offense_with_compound_guard_nil_first
    assert_no_offense(COP, <<~RUBY)
      def foo
        obj = event["actionable"]
        return if obj.nil? || skip?
        obj["nested"]
      end
    RUBY
  end

  def test_no_offense_with_compound_guard_nil_second
    # Regression: `return check_condition?` inside `any?` returned on the first
    # child, so a guard on the second branch was not recognized (false positive).
    assert_no_offense(COP, <<~RUBY)
      def foo
        obj = event["actionable"]
        return if skip? || obj.nil?
        obj["nested"]
      end
    RUBY
  end

  def test_no_offense_with_safe_navigation_guard
    assert_no_offense(COP, <<~RUBY)
      def foo
        obj = event["actionable"]
        return if obj&.empty?
        obj["nested"]
      end
    RUBY
  end

  def test_no_offense_with_literal_assignment
    assert_no_offense(COP, <<~RUBY)
      def foo
        obj = {}
        obj["key"]
      end
    RUBY
  end

  def test_no_offense_with_truthy_guard
    assert_no_offense(COP, <<~RUBY)
      def foo
        obj = event["actionable"]
        return unless obj
        obj["nested"]
      end
    RUBY
  end
end
