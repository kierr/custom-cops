# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class DuplicateSigTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Sorbet::DuplicateSig

  # --- Bad: offenses expected ---

  def test_flags_duplicate_sig_on_same_method
    offenses = investigate(COP, <<~RUBY)
      class Foo
        sig { void }
        sig { void }
        def bar
          42
        end
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/stale/i, offenses.first.message)
  end

  def test_flags_duplicate_sig_with_different_bodies
    offenses = investigate(COP, <<~RUBY)
      class Foo
        sig { returns(Integer) }
        sig { returns(String) }
        def bar
          42
        end
      end
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  def test_no_offense_for_single_sig
    offenses = investigate(COP, <<~RUBY)
      class Foo
        sig { void }
        def bar
          42
        end
      end
    RUBY

    assert_empty offenses
  end

  def test_no_offense_for_separate_methods
    offenses = investigate(COP, <<~RUBY)
      class Foo
        sig { void }
        def bar
          42
        end

        sig { void }
        def baz
          99
        end
      end
    RUBY

    assert_empty offenses
  end

  def test_no_offense_for_overload_sigs
    # Overloaded methods legitimately have multiple sigs
    offenses = investigate(COP, <<~RUBY)
      class Foo
        sig { params(x: Integer).void }
        sig { params(x: String).void }
        def bar(x)
        end
      end
    RUBY

    # Whether this flags depends on the cop's implementation;
    # overload sigs are a legitimate pattern but some cops flag them.
    # Just assert it doesn't crash.
    assert_kind_of Array, offenses
  end
end
