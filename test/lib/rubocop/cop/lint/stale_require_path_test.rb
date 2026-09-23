# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class StaleRequirePathTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::StaleRequirePath

  # StaleRequirePath checks `require_dependency` paths against the real
  # filesystem. Because it resolves paths relative to `Dir.pwd`, tests must
  # either run from a known directory tree or use `Dir.chdir` with a temp
  # structure. The cop only fires on `require_dependency`, not `require` or
  # `require_relative`.

  def test_flags_require_dependency_for_nonexistent_path
    # In a temp dir, no file exists, so any require_dependency path is stale.
    Dir.mktmpdir do |dir|
      offenses = Dir.chdir(dir) do
        investigate(COP, "require_dependency 'nonexistent/path'")
      end

      assert_equal 1, offenses.size
      assert_match(/does not resolve/, offenses.first.message)
    end
  end

  def test_no_offense_when_file_exists
    Dir.mktmpdir do |dir|
      # Create a file at lib/my_module.rb so the path resolves
      lib_dir = File.join(dir, 'lib')
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(lib_dir, 'my_module.rb'), '# test')

      offenses = Dir.chdir(dir) do
        investigate(COP, "require_dependency 'my_module'")
      end

      assert_empty offenses
    end
  end

  def test_no_offense_for_require_not_require_dependency
    offenses = investigate(COP, "require 'nonexistent/path'")

    assert_empty offenses
  end

  def test_no_offense_for_empty_path
    offenses = investigate(COP, "require_dependency ''")

    assert_empty offenses
  end
end
