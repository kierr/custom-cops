# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class ConstantInsideMethodTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::ConstantInsideMethod

  # DECISION: This cop is NOT wired and must not be enabled. Dynamic constant
  # assignment (`CONST = x` inside a method) is a Ruby SyntaxError, so real
  # offenses never parse. The cop can only produce false positives. These tests
  # confirm the cop loads without error and correctly skips non-offending code.

  def test_no_offense_for_method_without_constant
    offenses = investigate(COP, <<~RUBY)
      def configure
        settings = load_config
        apply(settings)
      end
    RUBY

    assert_empty offenses
  end

  def test_no_offense_for_class_level_constant
    offenses = investigate(COP, <<~RUBY)
      class Worker
        MAX_RETRIES = 3

        def run
          attempt
        end
      end
    RUBY

    assert_empty offenses
  end

  def test_no_offense_for_hash_rocket_key
    offenses = investigate(COP, <<~RUBY)
      def defaults
        { MAX_RETRIES => 3 }
      end
    RUBY

    assert_empty offenses
  end
end
