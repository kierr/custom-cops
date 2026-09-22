# typed: false # RuboCop cop — T is undefined at load time
# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module CustomCops
      # Shared `allowed_path?` check for the `NoDirect*` cops that each keep a
      # per-gem `ALLOWED_PATHS` constant of adapter/platform/test prefixes where
      # direct usage is permitted. Extracted from four byte-identical copies;
      # the including cop supplies `ALLOWED_PATHS` (a frozen Array<String>).
      #
      # NOTE: no `extend T::Helpers` / `requires_ancestor { Base }` — Sorbet's
      # T is undefined during RuboCop's require phase (see typed: false above);
      # include this module only in RuboCop::Cop::Base subclasses.
      module AllowedPaths
        private

        def allowed_path?
          path = processed_source.file_path.to_s
          self.class::ALLOWED_PATHS.any? { |pattern| path.include?(pattern) }
        end
      end
    end
  end
end
