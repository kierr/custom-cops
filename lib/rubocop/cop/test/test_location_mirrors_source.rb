# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Test
      # Enforces that test files mirror their source file location.
      # A test at `test/<dir>/<path>_test.rb` must test a source at
      # `app/<dir>/<path>.rb`. When a source file moves between `app/`
      # directories (e.g. `app/models/` → `app/lib/`), its test must follow.
      #
      # Only checks directories where the convention applies: lib, models,
      # services, controllers, consumers, concerns, contracts, errors, jobs,
      # middleware, serializers, value_objects.
      #
      # @example
      #
      #   # bad — test in test/models/ but source is at app/lib/
      #   # test/models/order_catalog_test.rb
      #   # app/lib/order_catalog.rb  ← source lives here
      #
      #   # good — test mirrors source location
      #   # test/lib/order_catalog_test.rb
      #   # app/lib/order_catalog.rb
      #
      class TestLocationMirrorsSource < Base
        MSG = 'Test at `test/%<test_dir>s` but source is at `app/%<source_dir>s`. ' \
              'Move this test to `test/%<source_dir>s/%<name>s` to mirror the source location.'

        MAPPED_DIRS = %w[lib models services controllers consumers concerns contracts errors jobs middleware serializers value_objects].freeze

        # Directories exempt from this check — test infrastructure, not testing a source file.
        EXEMPT_TEST_DIRS = %w[
          support fixtures factories cassettes config lint rubocop
          integration system deprecations utilities unit routing
          amazon sites value_objects
        ].freeze

        def on_new_investigation
          file_path = processed_source.file_path
          return unless test_file?(file_path)

          test_rel = test_relative_path(file_path)
          return unless test_rel
          return if exempt_test_dir?(test_rel)

          test_dir = File.dirname(test_rel)
          test_basename = File.basename(test_rel, '.rb')
          return unless test_basename.end_with?('_test')

          source_basename = test_basename.sub(/_test$/, '')
          source_rel = File.join(test_dir, "#{source_basename}.rb")

          return if source_exists?(file_path, source_rel)

          # Find where the source actually lives.
          actual_dir = find_source_dir(file_path, test_dir, source_basename)
          return unless actual_dir

          # Source exists but in a different app/ directory — flag it.
          loc = processed_source.ast&.loc&.expression
          return unless loc

          add_offense(
            loc,
            message: format(MSG, test_dir: test_dir, source_dir: actual_dir, name: File.join(actual_dir, "#{source_basename}_test.rb"))
          )
        end

        private

        def test_file?(file_path)
          file_path.include?('/test/') && file_path.end_with?('_test.rb')
        end

        # Returns the path relative to test/ (e.g. "lib/foo_test.rb", "models/bar_test.rb").
        def test_relative_path(file_path)
          match = file_path[%r{/test/(.+)_test\.rb\z}, 1]
          return nil unless match

          "#{match}_test.rb"
        end

        def exempt_test_dir?(test_rel)
          top_dir = test_rel.split('/').first
          EXEMPT_TEST_DIRS.include?(top_dir)
        end

        # True if the source file exists at the expected mirror location.
        def source_exists?(file_path, source_rel)
          app_root = extract_app_root(file_path)
          return false unless app_root

          File.exist?(File.join(app_root, source_rel))
        end

        # Searches all app/ subdirectories for the source file.
        # Returns the directory name where found, or nil.
        def find_source_dir(file_path, expected_dir, source_basename)
          app_root = extract_app_root(file_path)
          return nil unless app_root

          MAPPED_DIRS.each do |dir|
            next if dir == expected_dir

            candidate = File.join(app_root, dir, source_basename)
            return dir if File.exist?("#{candidate}.rb")
          end

          nil
        end

        def extract_app_root(file_path)
          file_path[%r{\A(.*?/app)/}, 1]
        end
      end
    end
  end
end
