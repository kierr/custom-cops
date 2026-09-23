# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class BlankLineBetweenSigilAndPragmaTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Sorbet::BlankLineBetweenSigilAndPragma

  # --- Bad: offenses expected ---

  def test_flags_blank_line_between_sigil_and_pragma
    offenses = investigate(COP, <<~RUBY)
      # typed: strict

      # frozen_string_literal: true
      class Foo; end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/blank line/, offenses.first.message)
  end

  def test_flags_multiple_blank_lines
    offenses = investigate(COP, <<~RUBY)
      # typed: strong


      # frozen_string_literal: true
      class Foo; end
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  def test_no_offense_when_adjacent
    offenses = investigate(COP, <<~RUBY)
      # typed: strict
      # frozen_string_literal: true
      class Foo; end
    RUBY

    assert_empty offenses
  end

  def test_no_offense_without_frozen_pragma
    offenses = investigate(COP, <<~RUBY)
      # typed: strict

      class Foo; end
    RUBY

    assert_empty offenses
  end

  def test_no_offense_without_typed_sigil
    offenses = investigate(COP, <<~RUBY)

      # frozen_string_literal: true
      class Foo; end
    RUBY

    assert_empty offenses
  end
end
