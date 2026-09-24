# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

# Tests for Lint/RegexSpaceInVerboseModeBody, which flags literal spaces in
# verbose-mode (`/x`) regex bodies where the engine ignores them.
class RegexSpaceInVerboseModeBodyTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::RegexSpaceInVerboseModeBody

  def test_flags_literal_space_in_verbose_regex
    offenses = investigate(COP, '/foo bar/x')

    assert_equal 1, offenses.size
    assert_match(/Literal space.*ignored/, offenses.first.message)
  end

  def test_flags_multiple_literal_spaces
    # The cop reports one offense per regex (intentional — the message
    # describes the general problem, not each space).
    offenses = investigate(COP, '/foo bar baz/x')

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'escaped_space' => '/foo\\ bar/x',
    'space_in_character_class' => '/foo[ ]bar/x',
    'non_verbose_regex_space_ok' => '/foo bar/',
    'space_adjacent_to_pipe' => '/foo | bar/x',
    'space_adjacent_to_paren' => '/( foo )/x',
    'space_at_start' => '/ foo/x',
    'no_space' => '/foobar/x'
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      assert_no_offense(COP, source)
    end
  end
end
