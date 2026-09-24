# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class DuplicateBranchBodyTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Style::DuplicateBranchBody

  # --- Bad: offenses expected ---

  def test_flags_identical_method_calls_in_if_else
    offenses = investigate(COP, <<~RUBY)
      if x
        add_offense(node, message: MSG)
      else
        add_offense(node, message: MSG)
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/identical method calls/, offenses.first.message)
  end

  def test_flags_identical_simple_method_calls
    offenses = investigate(COP, <<~RUBY)
      if condition_a
        process(item)
      else
        process(item)
      end
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'different_methods' => "if x\n  process_a(item)\nelse\n  process_b(item)\nend",
    'different_args' => "if x\n  add_offense(node, message: MSG_A)\nelse\n  add_offense(node, message: MSG_B)\nend",
    'elsif_chain' => "if x\n  handle_a\nelsif y\n  handle_b\nelse\n  handle_c\nend",
    'ternary' => 'x ? process(item) : process(item)',
    'multi_statement_branch' => "if x\n  log('a')\n  process(item)\nelse\n  process(item)\nend",
    'different_receivers' => "if x\n  foo.process(item)\nelse\n  bar.process(item)\nend"
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses, "Expected no offense for #{name}"
    end
  end
end
