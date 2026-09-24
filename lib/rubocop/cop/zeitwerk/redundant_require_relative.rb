# typed: strict
# frozen_string_literal: true

require_relative '../../custom_cops/zeitwerk_ignore_parser'

module RuboCop
  module Cop
    module Zeitwerk
      # Detects `require_relative` calls in `app/` where the target file is NOT
      # in the Zeitwerk ignore list. These calls are unnecessary because Zeitwerk
      # autoloads constants from files it manages. Only files explicitly ignored
      # from autoloading need manual `require_relative`.
      #
      # @example
      #   # bad — target is autoloaded by Zeitwerk, require_relative is redundant
      #   require_relative 'some_constant'
      #   require_relative 'another_constant'
      #
      #   # good — target is in the Zeitwerk ignore list (multi-constant file)
      #   require_relative 'my_api_responses'
      #
      class RedundantRequireRelative < Base
        MSG = 'Redundant `require_relative` — target is autoloaded by Zeitwerk. Remove the call and reference the constant directly.'

        def self.reset!
          ::RuboCop::Cop::CustomCops::ZeitwerkIgnoreParser.reset!
        end

        def on_send(node)
          return unless processed_source.file_path.include?('/app/')
          return unless node.method_name == :require_relative
          return unless node.first_argument&.str_type?

          # RATIONALE: source-file-is-ignored — when the file containing the
          # require_relative is itself Zeitwerk-ignored, its requires are
          # intentional barrel-file loads, not redundant autoloads. Ignored
          # barrel files (e.g. my_api_responses.rb) define no constants
          # and exist solely to assemble their siblings via require_relative;
          # flagging those calls would defeat the file's purpose. Would need
          # barrel files to stop being ignored to reconsider.
          return if source_ignored?

          target_path = resolve_target(node)
          return if target_path.nil?
          return if ignored?(target_path)

          add_offense(node, message: MSG)
        end

        private

        def source_ignored?
          source_path = current_source_path
          return false if source_path.nil?

          ignored?(source_path)
        end

        def current_source_path
          absolute = processed_source.file_path
          pwd = Dir.pwd
          return nil unless absolute.start_with?(pwd)

          absolute.delete_prefix("#{pwd}/")
        end

        def resolve_target(node)
          relative = node.first_argument.value
          source_dir = File.dirname(processed_source.file_path)
          absolute = File.expand_path(relative, source_dir)
          # Ruby appends .rb when loading require_relative without extension
          absolute = "#{absolute}.rb" unless absolute.end_with?('.rb')
          pwd = Dir.pwd
          return nil unless absolute.start_with?(pwd)

          absolute.delete_prefix("#{pwd}/")
        end

        def ignored?(target_path)
          ::RuboCop::Cop::CustomCops::ZeitwerkIgnoreParser.ignored_paths.any? do |ignored|
            target_path == ignored || target_path.start_with?("#{ignored}/")
          end
        end
      end
    end
  end
end
