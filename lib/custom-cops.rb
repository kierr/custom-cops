# typed: strict
# frozen_string_literal: true

require 'rubocop'
require 'sorbet-runtime'

require_relative 'rubocop/custom_cops/version'
require_relative 'rubocop/custom_cops/inject'
require_relative 'rubocop/custom_cops/cops'

RuboCop::CustomCops::Inject.defaults!

# Backward-compatibility alias: the gem was originally published as
# `RuboCop::Kierr` / `RuboCop::Cop::Kierr`. Downstream consumers (notably the
# Autosis Rails app) `include ::RuboCop::Cop::Kierr::CommentWindow` and
# `::RuboCop::Cop::Kierr::AllowedPaths` in their own cops. Aliasing the old
# namespace to the new one lets them consume the upstream gem with no code
# changes, so they can stop vendoring a stale copy. Autosis's own cops
# reference only these two mixins (verified: no ZeitwerkIgnoreParser, Inject,
# or VERSION references in its non-vendor tree).
module RuboCop
  Kierr = CustomCops
end

module RuboCop
  module Cop
    Kierr = CustomCops
  end
end
