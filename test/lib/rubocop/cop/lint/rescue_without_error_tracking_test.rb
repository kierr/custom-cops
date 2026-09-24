# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

# Tests for Lint/RescueWithoutErrorTracking, which flags `rescue => e` blocks
# that bind the exception variable but never reference it in the body.
class RescueWithoutErrorTrackingTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::RescueWithoutErrorTracking

  def test_flags_bound_exception_variable_never_referenced
    offenses = investigate(COP, <<~RUBY)
      begin
        do_thing
      rescue => e
        logger.error('failed')
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/Exception variable.*bound but never referenced/, offenses.first.message)
  end

  def test_flags_named_exception_class_with_unused_variable
    offenses = investigate(COP, <<~RUBY)
      begin
        do_thing
      rescue StandardError => e
        ServiceResult.failure(message: 'unknown error')
      end
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  def test_no_offense_for_bare_raise
    # Bare `raise` re-raises the caught exception; the variable propagates
    # the error even though it is not textually referenced.
    assert_no_offense(COP, <<~RUBY)
      begin
        do_thing
      rescue => e
        logger.error('unexpected_failure')
        raise
      end
    RUBY
  end

  def test_no_offense_for_variable_used_in_log
    assert_no_offense(COP, <<~RUBY)
      begin
        do_thing
      rescue => e
        logger.error('operation_failed', error_class: e.class.name, error_message: e.message)
      end
    RUBY
  end

  def test_no_offense_for_variable_used_in_raise
    assert_no_offense(COP, <<~RUBY)
      begin
        do_thing
      rescue => e
        raise CustomError, "wrapped: \#{e.message}"
      end
    RUBY
  end

  def test_no_offense_for_no_variable_binding
    # Bare `rescue StandardError` with no `=>` binding is out of scope for
    # this cop (handled by RescueWithoutExceptionBinding if present).
    assert_no_offense(COP, <<~RUBY)
      begin
        do_thing
      rescue StandardError
        nil
      end
    RUBY
  end
end
