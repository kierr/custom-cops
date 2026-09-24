# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

# Tests for Lint/InsertAllNotUpsertAll, which flags `insert_all(..., unique_by:)`
# — the shape where unique_by implies upsert intent but insert_all silently
# skips duplicates (ON CONFLICT DO NOTHING). Bare insert_all (no unique_by) is
# the legitimate DO NOTHING pattern and is not flagged.
class InsertAllNotUpsertAllTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::InsertAllNotUpsertAll

  def test_flags_insert_all_with_unique_by
    offenses = investigate(COP, 'Person.insert_all(rows, unique_by: :uuid)')

    assert_equal 1, offenses.size
    assert_match(/upsert_all/, offenses.first.message)
  end

  def test_no_offense_for_bare_insert_all
    assert_no_offense(COP, 'Person.insert_all(rows)')
  end

  def test_no_offense_for_upsert_all
    assert_no_offense(COP, 'Person.upsert_all(rows, unique_by: :uuid)')
  end

  def test_no_offense_for_insert_all_with_returning
    assert_no_offense(COP, 'Person.insert_all(rows, returning: :id)')
  end
end
