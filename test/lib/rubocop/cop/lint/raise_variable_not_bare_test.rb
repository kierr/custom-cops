# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class RaiseVariableNotBareTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::RaiseVariableNotBare

  # --- Bad: offenses expected ---

  def test_flags_raise_with_rescue_variable
    offenses = investigate(COP, <<~RUBY)
      begin
        do_work
      rescue StandardError => e
        logger.error e.message
        raise e
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/bare/, offenses.first.message)
  end

  def test_flags_kernel_raise_with_rescue_variable
    offenses = investigate(COP, <<~RUBY)
      begin
        do_work
      rescue => e
        Kernel.raise e
      end
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_bare_rescue_variable
    offenses = investigate(COP, <<~RUBY)
      begin
        do_work
      rescue => e
        raise e
      end
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'bare_raise' => "begin\n  do_work\nrescue => e\n  raise\nend",
    'raise_different_variable' => "begin\n  do_work\nrescue => e\n  raise other_error\nend",
    'raise_with_string' => "begin\n  do_work\nrescue => e\n  raise 'failed'\nend",
    'raise_with_exception_class' => "begin\n  do_work\nrescue => e\n  raise StandardError, 'msg'\nend",
    'raise_outside_rescue' => "def check\n  raise err\nend",
    'raise_with_new_exception' => "begin\n  do_work\nrescue => e\n  raise SomeError.new(e.message)\nend"
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses, "Expected no offense for #{name}"
    end
  end
end
