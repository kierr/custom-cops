# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class DateNewWithUnguardedArgumentsTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::DateNewWithUnguardedArguments

  # --- Bad: offenses expected ---

  def test_flags_method_arg_as_year
    offenses = investigate(COP, <<~RUBY)
      def build_date(year)
        Date.new(year, 1, 1)
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/Date\.new/, offenses.first.message)
  end

  OFFENSE_CASES = {
    'hash_access_arguments' => 'Date.new(params[:year], params[:month], params[:day])',
    'instance_variable' => 'Date.new(@year, @month, @day)',
    'single_dynamic_arg_among_literals' => 'Date.new(year, 1, 1)',
    'method_call_argument' => 'Date.new(calculate_year(data), 6, 15)',
    'when_only_some_dynamic_args_sanitized' => 'Date.new(NumericUtil.safe_int(year), month, 1)'
  }.freeze

  OFFENSE_CASES.each do |name, source|
    define_method(:"test_flags_#{name}") do
      offenses = investigate(COP, source)

      assert_equal 1, offenses.size
    end
  end

  def test_flags_local_variable_from_method_call
    offenses = investigate(COP, <<~RUBY)
      year = extract_year(raw)
      month = extract_month(raw)
      Date.new(year, month, 1)
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'all_literal_integers' => 'Date.new(2025, 1, 15)',
    'numeric_util_safe_int' => 'Date.new(NumericUtil.safe_int(year), NumericUtil.safe_int(month), 1)',
    'trusted_date_component_accessors' => 'Date.new(today.year, today.month, 1)',
    'time_current_component_accessors' => 'Date.new(Time.current.year, Time.current.month, 1)',
    'non_date_receiver' => 'CustomDate.new(year, month, day)',
    'mixed_sanitized_and_literal_args' => 'Date.new(NumericUtil.safe_int(year), 6, 15)'
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses
    end
  end

  NO_OFFENSE_2_CASES = {
    'rescue_argument_error' => "begin\n  Date.new(year, month, day)\nrescue ArgumentError\n  nil\nend",
    'rescue_standard_error' => "begin\n  Date.new(year, month, day)\nrescue StandardError\n  nil\nend",
    'rescue_type_error' => "begin\n  Date.new(year, month, day)\nrescue TypeError\n  nil\nend",
    'bare_rescue' => "begin\n  Date.new(year, month, day)\nrescue\n  nil\nend",
    'method_def_with_rescue' => "def build_date(year, month, day)\n  Date.new(year, month, day)\nrescue ArgumentError\n  nil\nend"
  }.freeze

  NO_OFFENSE_2_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses
    end
  end

  def test_no_offense_for_constant_reference_argument
    offenses = investigate(COP, <<~RUBY)
      DEFAULT_MONTH = 1
      DEFAULT_DAY = 15
      Date.new(2025, DEFAULT_MONTH, DEFAULT_DAY)
    RUBY

    assert_empty offenses
  end

  def test_no_offense_for_nested_rescue_in_method
    offenses = investigate(COP, <<~RUBY)
      def process(raw)
        year = parse_year(raw)
        begin
          Date.new(year, 1, 1)
        rescue ArgumentError
          Date.new(2000, 1, 1)
        end
      end
    RUBY

    assert_empty offenses
  end
end
