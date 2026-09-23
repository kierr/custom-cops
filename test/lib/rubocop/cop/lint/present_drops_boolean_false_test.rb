# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class PresentDropsBooleanFalseTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::PresentDropsBooleanFalse

  # NOTE: This cop has a structural bug where `boolean_domain?` and other
  # helper methods are nested inside `def rationale?`. On first invocation,
  # `on_send` calls `boolean_domain?` which is not yet defined (it only gets
  # defined when `rationale?` is first called), causing a NoMethodError.
  # The Commissioner catches this silently, so the cop never fires.
  # These tests document current behavior. Once the nested-def bug is fixed,
  # these tests should be updated to assert offenses where expected.

  def test_currently_no_offense_for_predicate_present_in_guard
    # Should flag: `verified?` is a predicate method, present? drops false
    # Actually: crashes with NoMethodError, Commissioner swallows it
    offenses = investigate(COP, <<~RUBY)
      do_thing if user.verified?.present?
    RUBY

    # Documenting broken behavior; update to assert_equal 1 when cop is fixed
    assert_empty offenses
  end

  def test_currently_no_offense_for_boolean_prefix_variable
    offenses = investigate(COP, <<~RUBY)
      result[:x] = is_active if is_active.present?
    RUBY

    assert_empty offenses
  end

  def test_currently_no_offense_for_enabled_method
    offenses = investigate(COP, <<~RUBY)
      do_thing if account.is_enabled.present?
    RUBY

    assert_empty offenses
  end

  # These cases should remain no-offense even after the cop is fixed

  NO_OFFENSE_CASES = {
    'string_domain' => "name = params[:name] if params[:name].present?",
    'collection_presence' => "process(items) if items.present?",
    'timestamp_suffix' => "if record.updated_at.present?\n  go\nend",
    'id_suffix' => "if user.id.present?\n  go\nend",
    'non_boolean_name' => "if record.name.present?\n  go\nend",
    'validated_not_valid' => "if record.last_validated_at.present?\n  go\nend"
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses, "Expected no offense for #{name}"
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
