# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

# Tests for Style/GuardClauseInversion.
#
# The cop is disabled in config/default.yml because its premise is unsound:
# `return unless X; handle(X-true case)` is idiomatic correct Ruby (guard out
# the uninteresting case, then handle the case of interest). A full audit found
# 0 real bugs and 14 false positives. These tests assert the disabled state so
# re-enabling is a visible decision, not a silent regression.
class GuardClauseInversionTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Style::GuardClauseInversion

  # The cop is disabled, so the idiomatic guard shape produces no offenses.
  # If re-enabled, this test would catch the false positive.
  def test_disabled_so_no_offense_for_idiomatic_guard
    assert_no_offense(COP, <<~RUBY)
      def wait
        return unless wait_thr.alive?
        kill(wait_thr)
        raise Timeout
      end
    RUBY
  end

  def test_disabled_so_no_offense_for_guard_then_raise
    assert_no_offense(COP, <<~RUBY)
      def validate
        return unless samesite == 'None' && !secure
        raise InvalidCookie
      end
    RUBY
  end
end
