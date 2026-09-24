# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class PresentDropsBooleanFalseTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::PresentDropsBooleanFalse

  # --- Bad: offenses expected ---

  def test_flags_predicate_method_present_in_guard
    offenses = investigate(COP, <<~RUBY)
      do_thing if user.verified?.present?
    RUBY

    assert_equal 1, offenses.size
    assert_match(/present\?/, offenses.first.message)
  end

  def test_flags_boolean_prefix_method_present_in_guard
    offenses = investigate(COP, <<~RUBY)
      do_thing if account.is_enabled.present?
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_boolean_prefix_variable_in_postfix_guard
    offenses = investigate(COP, <<~RUBY)
      result[:x] = is_active if is_active.present?
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_boolean_word_segment_in_guard
    offenses = investigate(COP, <<~RUBY)
      go if record.flag.present?
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_ternary_guard
    offenses = investigate(COP, <<~RUBY)
      user.verified?.present? ? do_thing : skip
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_boolean_operator_chain_in_guard
    offenses = investigate(COP, <<~RUBY)
      go if user.verified?.present? && other_condition
    RUBY

    assert_equal 1, offenses.size
  end

  def test_flags_sorbet_sig_t_boolean_return
    offenses = investigate(COP, <<~RUBY)
      sig { returns(T.nilable(T::Boolean)) }
      def feature_enabled?
        @enabled
      end
      do_thing if feature_enabled?.present?
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'string_domain' => 'name = params[:name] if params[:name].present?',
    'collection_presence' => 'process(items) if items.present?',
    'timestamp_suffix' => "if record.updated_at.present?\n  go\nend",
    'id_suffix' => "if user.id.present?\n  go\nend",
    'non_boolean_name' => "if record.name.present?\n  go\nend",
    'validated_not_valid' => "if record.last_validated_at.present?\n  go\nend",
    'not_in_guard' => "value = user.verified?.present?\nputs value",
    'explicit_nil_check' => 'do_thing if !user.verified?.nil?'
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      assert_no_offense(COP, source)
    end
  end

  def test_no_offense_with_rationale_comment
    offenses = investigate(COP, <<~RUBY)
      # RATIONALE: tri-state coerced to truthy
      do_thing if user.verified?.present?
    RUBY

    assert_empty offenses
  end
end
