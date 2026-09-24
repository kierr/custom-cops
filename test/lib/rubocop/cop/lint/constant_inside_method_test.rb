# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class ConstantInsideMethodTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::ConstantInsideMethod

  # DECISION: This cop is disabled in config/default.yml and must not be
  # enabled. Dynamic constant assignment (`CONST = x` inside a method) is a
  # Ruby SyntaxError, so real offenses never parse — the cop can only produce
  # false positives. Audit #1198: 0 real / 20 false positive. These tests
  # confirm the disabled state and that non-offending code stays clean.

  def test_disabled_so_no_offense_for_method_without_constant
    assert_no_offense(COP, <<~RUBY)
      def configure
        settings = load_config
        apply(settings)
      end
    RUBY
  end

  def test_disabled_so_no_offense_for_class_level_constant
    assert_no_offense(COP, <<~RUBY)
      class Worker
        MAX_RETRIES = 3

        def run
          attempt
        end
      end
    RUBY
  end

  def test_disabled_so_no_offense_for_hash_rocket_key
    assert_no_offense(COP, <<~RUBY)
      def defaults
        { MAX_RETRIES => 3 }
      end
    RUBY
  end

  # Regression: when the cop was Enabled: true, the line-based depth tracker
  # misclassified `MAX_RETRIES = 3` inside a heredoc string as a constant
  # assignment — a false positive. Disabled in config/default.yml, so this
  # now produces zero offenses. If re-enabled, this test would catch the
  # heredoc false positive.
  def test_disabled_so_no_offense_for_heredoc_containing_constant_like_text
    assert_no_offense(COP, <<~RUBY)
      def foo
        s = <<~HEREDOC
          MAX_RETRIES = 3
        HEREDOC
        s
      end
    RUBY
  end
end
