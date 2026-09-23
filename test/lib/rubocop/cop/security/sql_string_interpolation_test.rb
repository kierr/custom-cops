# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class SqlStringInterpolationTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Security::SQLStringInterpolation

  # --- Bad: offenses expected ---

  def test_flags_interpolation_in_connection_execute
    offenses = investigate(COP, <<~RUBY)
      connection.execute("SELECT * FROM users WHERE id = \#{user.id}")
    RUBY

    assert_equal 1, offenses.size
    assert_match(/parameterized/i, offenses.first.message)
  end

  def test_flags_interpolation_in_exec_query
    offenses = investigate(COP, <<~RUBY)
      connection.exec_query("SELECT * FROM users WHERE id = \#{user.id}", 'SQL', [])
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_interpolation_in_select_all
    offenses = investigate(COP, <<~RUBY)
      connection.select_all("SELECT * FROM users WHERE id = \#{user.id}")
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'plain_string' => "connection.execute('SELECT 1')",
    'non_connection_method' => "log(\"Processing \#{item}\")",
    'parameterized_execute' => "connection.exec_query('SELECT * FROM users WHERE id = $1', 'SQL', binds)"
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses, "Expected no offense for #{name}"
    end
  end
end
