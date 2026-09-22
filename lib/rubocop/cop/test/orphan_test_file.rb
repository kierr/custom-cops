# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Test
      # Catches test files where the corresponding implementation file doesn't exist.
      #
      # Derives the expected class under test from the test file path using Zeitwerk
      # conventions, then checks if the implementation file exists in app/ or lib/.
      #
      # test/services/foo/bar_service_test.rb → app/services/foo/bar_service.rb
      # test/lib/my_module/helper_test.rb → lib/my_module/helper.rb OR app/lib/my_module/helper.rb
      # test/acme/consumers/X_test.rb → app/consumers/acme/X.rb (namespace remap)
      #
      # Search strategy:
      #   1. Direct path: app/<relative>, lib/<relative>, app/lib/<relative>
      #   2. Namespace remap: test/<ns>/X → app/{consumers,services,models,jobs,controllers}/<ns>/X
      #   3. Directory match: test/<path>/foo_bar_test.rb → check for app/<path>/foo_bar/ directory
      class OrphanTestFile < Base
        MSG = 'Test file has no corresponding implementation in app/ or lib/ (expected %<expected_path>s).'

        # Top-level app/ subdirectories to check during namespace remapping.
        APP_SUBDIRS = %w[consumers services models jobs controllers bots concerns lib].freeze

        def on_new_investigation
          file_path = processed_source.file_path
          return unless file_path.end_with?('_test.rb')
          return unless file_path.include?('/test/')

          test_idx = file_path.index('/test/')
          return unless test_idx

          project_root = file_path[0...test_idx]
          relative = file_path[(test_idx + 6)..] # strip /test/
          impl_relative = relative.sub(/_test\.rb$/, '.rb')

          return if impl_file_exists?(project_root, impl_relative)

          add_orphan_offense(impl_relative)
        end

        private

        def impl_file_exists?(project_root, impl_relative)
          # Direct path check: app/<relative>, lib/<relative>, app/lib/<relative>
          return true if direct_match?(project_root, impl_relative)

          # Namespace remap: test/<ns>/X → app/{subdir}/<ns>/X
          return true if namespace_remap_match?(project_root, impl_relative)

          # Directory match: foo_bar_test.rb → app/<path>/foo_bar/ directory
          return true if directory_match?(project_root, impl_relative)

          false
        end

        # Check app/<relative>, lib/<relative>, app/lib/<relative> directly
        def direct_match?(project_root, impl_relative)
          if impl_relative.start_with?('lib/')
            File.exist?(File.join(project_root, impl_relative)) ||
              File.exist?(File.join(project_root, 'app', impl_relative))
          else
            %w[app lib].any? { |dir| File.exist?(File.join(project_root, dir, impl_relative)) } ||
              File.exist?(File.join(project_root, 'app', 'lib', impl_relative))
          end
        end

        # Handle test/<ns>/X_test.rb where source exists in app/<subdir>/<ns>/X.rb
        # e.g., test/acme/consumers/foo_test.rb → app/consumers/acme/foo_test.rb
        # The test directory nests by domain (acme), but app/ nests by layer first.
        def namespace_remap_match?(project_root, impl_relative)
          parts = impl_relative.split('/')
          return false unless parts.length >= 2

          # Build all candidate paths upfront, then check in a single pass.
          # Avoids O(prefix_depth × APP_SUBDIRS) File.exist? calls with repeated
          # directory traversal — each candidate is built once.
          candidates = []
          (0...(parts.length - 1)).each do |prefix_depth|
            domain_parts = parts[0..prefix_depth]
            file_part = parts[(prefix_depth + 1)..]
            next if file_part.empty?

            APP_SUBDIRS.each do |subdir|
              candidates << File.join(project_root, 'app', subdir, *domain_parts, *file_part)
            end
          end

          candidates.any? { |c| File.exist?(c) }
        end

        # Handle tests for a directory of capability/feature files
        # e.g., test/models/integration/sites/provider/provider_capabilities_test.rb
        # tests the directory app/models/integration/sites/provider/capabilities/
        def directory_match?(project_root, impl_relative)
          base = impl_relative.sub(/\.rb$/, '')
          # Check if a directory with the underscored name exists
          %w[app lib].each do |dir|
            dir_path = File.join(project_root, dir, base)
            return true if File.directory?(dir_path)

            # Also check singular variant — handles plurals like providers → provider.
            # Uses a simple /s$/ strip instead of ActiveSupport::Inflector to keep
            # the cop usable outside the Rails autoloader (e.g., standalone test runs).
            singular = base.end_with?('s') && base[-2] != 's' ? base[0...-1] : base
            return true if File.directory?(File.join(project_root, dir, singular))
          end
          false
        end

        def add_orphan_offense(impl_relative)
          range = Parser::Source::Range.new(processed_source.buffer, 0, 0)
          expected = if impl_relative.start_with?('lib/')
                       impl_relative
                     else
                       "app/#{impl_relative} or lib/#{impl_relative}"
                     end
          add_offense(range, message: format(MSG, expected_path: expected))
        end
      end
    end
  end
end
