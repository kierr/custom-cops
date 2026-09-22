# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Zeitwerk
      # Bans `require_relative` calls where the path escapes the current directory
      # (contains `..`). Zeitwerk resolves constants by name from autoloaded directories,
      # making path-based loading both redundant and fragile under refactoring.
      #
      # @example
      #   # bad
      #   require_relative '../concerns/job_policy'
      #   require_relative '../../lib/text/titleize'
      #
      #   # good — Zeitwerk autoloads the constant when referenced
      #   include JobPolicy
      #   Text::Titleize.call(value)
      #
      #   # good — same-directory require_relative (no escaping)
      #   require_relative 'error/base'
      #
      class NoEscapingRequireRelative < Base
        MSG = 'Avoid `require_relative` with escaping paths (`..`). Reference the constant directly and let Zeitwerk autoload it.'

        def on_send(node)
          return unless processed_source.file_path.include?('/app/')

          return unless node.method_name == :require_relative
          return unless node.first_argument&.str_type?

          path = node.first_argument.value
          return unless path.include?('..')

          add_offense(node, message: MSG)
        end
      end
    end
  end
end
