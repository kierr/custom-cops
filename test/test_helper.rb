# typed: ignore
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'custom-cops'
require 'minitest/autorun'
require 'rubocop'
require 'rubocop/ast'
require 'yaml'

# Shared helper for cop unit tests. Uses the RuboCop programmatic API
# (Commissioner + ProcessedSource) instead of shelling out to `bundle exec rubocop`.
# This avoids config/Include coupling and makes tests deterministic.
module CopTestHelper
  private

  # Lazy-loaded default config from the gem's config/default.yml.
  # This ensures cops that are Enabled: true in the gem config actually fire
  # when tested via the Commissioner API (which bypasses RuboCop's config
  # loading pipeline).
  def default_config
    @default_config ||= begin
      gem_root = Gem.loaded_specs['custom-cops']&.full_gem_path || File.expand_path('../..', __dir__)
      path = File.join(gem_root, 'config', 'default.yml')
      hash = YAML.safe_load_file(path, permitted_classes: [Symbol])
      RuboCop::Config.new(hash, path)
    end
  end

  # Investigate a source string with the given cop class.
  # Returns an Array of RuboCop::Offense.
  def investigate(cop_class, source, filename = 'test.rb')
    cop = cop_class.new
    # RUBY_VERSION is "3.4.8" — ProcessedSource expects a Numeric (e.g. 3.4).
    # Take major.minor only; patch level is irrelevant for AST parsing.
    ruby_version_for_ast = Float(RUBY_VERSION.split('.').first(2).join('.'))
    processed_source = RuboCop::AST::ProcessedSource.new(source, ruby_version_for_ast, filename)
    commissioner = RuboCop::Cop::Commissioner.new([cop])
    cop.instance_variable_set(:@config, default_config)
    report = commissioner.investigate(processed_source)
    report.cop_reports.flat_map(&:offenses)
  end

  # Assert that investigating source with the given cop produces at least one offense.
  def assert_offense(cop_class, source, filename = 'test.rb')
    offenses = investigate(cop_class, source, filename)
    assert offenses.any?, "Expected #{cop_class} to flag an offense, but none were found.\nSource:\n#{source}"
  end

  # Assert that investigating source with the given cop produces no offenses.
  def assert_no_offense(cop_class, source, filename = 'test.rb')
    offenses = investigate(cop_class, source, filename)
    assert offenses.empty?, "Expected no offenses from #{cop_class}, but got:\n#{offenses.map(&:message).join("\n")}\nSource:\n#{source}"
  end
end
