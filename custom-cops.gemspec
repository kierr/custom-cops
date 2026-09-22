# frozen_string_literal: true

require_relative 'lib/rubocop/custom_cops/version'

Gem::Specification.new do |spec|
  spec.name = 'custom-cops'
  spec.version = RuboCop::CustomCops::VERSION
  spec.authors = ['kierr']
  spec.summary = 'Generic RuboCop cops for Sorbet, Karafka, Rails, logging, and migration safety'
  spec.description = <<~DESC
    Collection of RuboCop cops covering lint, Sorbet, security, Rails, Karafka,
    migration safety, logging, service patterns, and more. Designed as reusable
    enforcement for Ruby projects using Sorbet, Karafka, and SemanticLogger.
  DESC
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.add_dependency 'rubocop', '>= 1.50'
  spec.add_dependency 'sorbet-runtime' # hard dep — all cops use typed: strict/strong

  spec.files = Dir.glob('{config,lib}/**/*')

  spec.metadata = {
    'rubygems_mfa_required' => 'true',
    'homepage_uri' => 'https://github.com/kierr/custom-cops',
    'source_code_uri' => 'https://github.com/kierr/custom-cops'
  }
end
