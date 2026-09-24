# typed: ignore
# frozen_string_literal: true

require_relative 'test_helper'

# Verifies the RuboCop::Kierr backward-compatibility alias. The gem was
# originally published as RuboCop::Kierr / RuboCop::Cop::Kierr; downstream
# consumers (notably the Autosis Rails app) `include ::RuboCop::Cop::Kierr::*`
# in their own cops. The alias lets them consume the renamed upstream gem
# with no code changes.
class KierrCompatAliasTest < Minitest::Test
  def test_kierr_namespace_aliases_to_custom_cops
    assert_equal RuboCop::CustomCops, RuboCop::Kierr
  end

  def test_kierr_cop_namespace_aliases_to_custom_cops_cop
    assert_equal RuboCop::Cop::CustomCops, RuboCop::Cop::Kierr
  end

  def test_kierr_comment_window_resolves
    assert defined?(RuboCop::Cop::Kierr::CommentWindow)
    assert_equal RuboCop::Cop::CustomCops::CommentWindow,
                 RuboCop::Cop::Kierr::CommentWindow
  end

  def test_kierr_allowed_paths_resolves
    assert defined?(RuboCop::Cop::Kierr::AllowedPaths)
    assert_equal RuboCop::Cop::CustomCops::AllowedPaths,
                 RuboCop::Cop::Kierr::AllowedPaths
  end

  def test_kierr_inject_resolves
    assert defined?(RuboCop::Kierr::Inject)
    assert_equal RuboCop::CustomCops::Inject, RuboCop::Kierr::Inject
  end

  # Simulate an Autosis cop including the mixin via the old namespace.
  # Use a named module (not Class.new(Base)) — RuboCop::Base enrolls
  # subclasses in the cop registry on inheritance, and an anonymous class
  # has nil name, which crashes Badge.for and pollutes the registry for
  # later tests.
  def test_autosis_style_include_resolves
    mod = Module.new do
      include ::RuboCop::Cop::Kierr::CommentWindow
    end
    assert_includes mod.ancestors, RuboCop::Cop::Kierr::CommentWindow
    assert_includes mod.ancestors, RuboCop::Cop::CustomCops::CommentWindow
  end
end
