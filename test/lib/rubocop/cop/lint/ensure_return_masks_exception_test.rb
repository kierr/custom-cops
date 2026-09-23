# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class EnsureReturnMasksExceptionTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::EnsureReturnMasksException

  # --- Bad: offenses expected ---

  def test_flags_method_call_as_last_expression
    offenses = investigate(COP, <<~RUBY)
      def fetch
        do_work
      ensure
        cleanup
        calculate_expires_in
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/implicitly returns a value/, offenses.first.message)
  end

  OFFENSE_CASES = {
    'variable_read_as_last_expression' => "def process\n  do_work\nensure\n  cleanup\n  @result\nend",
    'literal_true_as_last_expression' => "def run\n  execute\nensure\n  reset\n  true\nend"
  }.freeze

  OFFENSE_CASES.each do |name, source|
    define_method(:"test_flags_#{name}") do
      offenses = investigate(COP, source)

      assert_equal 1, offenses.size
    end
  end

  # --- Good: no offenses ---

  def test_no_offense_cleanup_only
    offenses = investigate(COP, <<~RUBY)
      def fetch
        do_work
      ensure
        cleanup
      end
    RUBY

    assert_empty offenses
  end

  NO_OFFENSE_CASES = {
    'ending_in_nil' => "def fetch\n  do_work\nensure\n  cleanup\n  nil\nend",
    'ending_in_raise' => "def fetch\n  do_work\nensure\n  cleanup\n  raise if $!\nend",
    'ending_in_explicit_return' => "def fetch\n  do_work\nensure\n  cleanup\n  return\nend",
    'ending_in_next' => "items.each do |item|\n  process(item)\nensure\n  cleanup\n  next\nend",
    'ending_in_break' => "items.each do |item|\n  process(item)\nensure\n  cleanup\n  break\nend",
    'ending_in_throw' => "def fetch\n  do_work\nensure\n  cleanup\n  throw :done\nend",
    'ending_in_assignment' => "def fetch\n  do_work\nensure\n  cleanup\n  @closed = true\nend",
    'ending_in_fail' => "def fetch\n  do_work\nensure\n  cleanup\n  fail \"boom\" if broken?\nend",
    'safe_navigation_cleanup' => "def fetch\n  do_work\nensure\n  tempfile.close\n  tempfile&.unlink\nend",
    'pool_wait_for_termination' => "def fetch\n  do_work\nensure\n  cleanup\n  pool&.wait_for_termination\nend",
    'or_chain_cleanup' => "def fetch\n  do_work\nensure\n  cleanup\n  pool.wait_for_termination(5) || pool.kill\nend"
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses
    end
  end

  def test_no_offense_empty_body
    offenses = investigate(COP, <<~RUBY)
      def fetch
        do_work
      ensure
      end
    RUBY

    assert_empty offenses
  end

  def test_no_offense_conditional_defined_check
    offenses = investigate(COP, <<~RUBY)
      def fetch
        do_work
      ensure
        cleanup
        if defined?(Yabeda)
          Yabeda.metric.record(1)
        end
      end
    RUBY

    assert_empty offenses
  end
end
