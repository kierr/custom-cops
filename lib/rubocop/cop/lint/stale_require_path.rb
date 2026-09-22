# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `require_dependency` calls with paths that do not resolve to
      # existing files. Stale paths cause LoadError at boot when files are
      # renamed without updating the require.
      #
      # @example
      #
      #   # bad — file was renamed
      #   require_dependency 'source/investigation_structs'
      #
      #   # good
      #   require_dependency 'source/investigation/types'
      class StaleRequirePath < Base
        MSG = '`require_dependency` path does not resolve to an existing file: `%<path>s`'

        def_node_matcher :require_dependency?, <<~PATTERN
          (send nil? :require_dependency $(str ...))
        PATTERN

        def on_send(node)
          path_node = require_dependency?(node)
          return unless path_node

          path = path_node.value
          return if path.empty?
          return if resolves_to_file?(path)

          add_offense(path_node, message: format(MSG, path: path))
        end

        private

        def resolves_to_file?(path)
          # Check common load path prefixes for the resolved file
          %w[app app/models app/services app/lib lib].each do |prefix|
            base = File.join(Dir.pwd, prefix)
            %w[.rb].each do |ext|
              candidate = File.join(base, "#{path}#{ext}")
              return true if File.file?(candidate)
            end

            # Also check if path already has extension
            candidate = File.join(base, path)
            return true if File.file?(candidate)
          end

          # Check if Zeitwerk would autoload it
          underscore_path = path.include?('/') ? path : path.gsub(%r{(?<!/)([A-Z])}, '_\1').downcase
          %w[app app/models app/services app/lib lib].each do |prefix|
            candidate = File.join(Dir.pwd, prefix, "#{underscore_path}.rb")
            return true if File.file?(candidate)
          end

          false
        end
      end
    end
  end
end
