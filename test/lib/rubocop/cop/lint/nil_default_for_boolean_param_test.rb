# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class NilDefaultForBooleanParamTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::NilDefaultForBooleanParam

  # --- Bad: offenses expected ---

  def test_flags_nil_default_for_boolean_kwoptarg
    offenses = investigate(COP, <<~RUBY)
      sig { params(shell: T::Boolean).void }
      def run!(cmd, shell: nil)
        execute(cmd, shell)
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/Boolean/, offenses.first.message)
  end

  def test_flags_nil_default_for_boolean_optarg
    offenses = investigate(COP, <<~RUBY)
      sig { params(force: T::Boolean).void }
      def process(force = nil)
        do_work(force)
      end
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'false_default' => "sig { params(force: T::Boolean).void }\ndef process(force: false)\n  do_work(force)\nend",
    'true_default' => "sig { params(force: T::Boolean).void }\ndef process(force: true)\n  do_work(force)\nend",
    'non_boolean_param_nil' => "sig { params(name: T.nilable(String)).void }\ndef process(name: nil)\n  do_work(name)\nend",
    'no_sig' => "def process(force: nil)\n  do_work(force)\nend",
    'no_default' => "sig { params(force: T::Boolean).void }\ndef process(force:)\n  do_work(force)\nend"
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses, "Expected no offense for #{name}"
    end
  end
end
