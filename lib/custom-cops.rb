# typed: strict
# frozen_string_literal: true

require 'rubocop'
require 'sorbet-runtime'

require_relative 'rubocop/custom_cops/version'
require_relative 'rubocop/custom_cops/inject'
require_relative 'rubocop/custom_cops/cops'

RuboCop::CustomCops::Inject.defaults!
