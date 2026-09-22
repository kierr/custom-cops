# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module CustomCops
      # Shared parser for Zeitwerk ignore paths extracted from
      # config/initializers/zeitwerk.rb. Used by cops that need to know which
      # files are intentionally excluded from autoloading.
      module ZeitwerkIgnoreParser
        @ignored_paths = []
        @loaded = false

        def self.ignored_paths
          load! unless @loaded
          @ignored_paths
        end

        def self.load!
          return if @loaded

          zeitwerk_path = File.join(Dir.pwd, 'config/initializers/zeitwerk.rb')
          return unless File.exist?(zeitwerk_path)

          content = File.read(zeitwerk_path)
          # `(?:\.to_s)?` — every ignore call in zeitwerk.rb appends `.to_s`
          # (push_dir/ignore take string args). Without it the regex matched
          # zero paths, so RedundantRequireRelative flagged every necessary
          # require of an ignored target (version.rb, ident/scoring.rb) as a
          # false positive. Would need a call site to drop `.to_s` to reconsider.
          @ignored_paths = content.scan(/\.ignore\(Rails\.root\.join\('([^']+)'\)(?:\.to_s)?\)/).flatten
          @loaded = true
        end

        def self.reset!
          @ignored_paths = []
          @loaded = false
        end
      end
    end
  end
end
