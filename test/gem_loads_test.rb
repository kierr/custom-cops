# frozen_string_literal: true

require_relative 'test_helper'

class GemLoadsTest < Minitest::Test
  def test_gem_loads_and_registers_cops
    cops = RuboCop::Cop::Registry.global.to_a
    custom = cops.reject { |c| c.badge.department == :InternalAffairs }
    refute_empty custom
  end

  def test_default_config_covers_all_cop_files
    config = YAML.safe_load_file(
      File.expand_path('../config/default.yml', __dir__),
      permitted_classes: [Symbol]
    )
    cop_files = Dir.glob(File.expand_path('../lib/rubocop/cop/**/*.rb', __dir__))
                   .reject { |f| f.end_with?('migration_safety/base.rb') }
    cop_names = cop_files.map do |f|
      relative = f.sub(%r{.*/lib/rubocop/cop/}, '').sub(/\.rb$/, '')
      relative.split('/').map { |part| part.split('_').map(&:capitalize).join }.join('/')
    end
    missing = cop_names.reject { |name| config.key?(name) }
    assert_empty missing, "cops missing from config/default.yml: #{missing.inspect}"
  end

  def test_version_matches_gemspec
    spec = Gem::Specification.load(File.expand_path('../custom-cops.gemspec', __dir__))
    assert_equal RuboCop::CustomCops::VERSION, spec.version.to_s
  end
end
