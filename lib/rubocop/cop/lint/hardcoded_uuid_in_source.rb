# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects hardcoded UUID string literals in source code (app/ and lib/).
      # Hardcoded UUIDs create undeclared coupling to specific database records.
      # When the record is re-seeded or migrated, the UUID changes and the code
      # silently breaks. Extract inline UUIDs to a named constant with a comment
      # identifying the record.
      #
      # UUIDs assigned to constants (e.g., `SOURCE_ID = '018d...'`) are accepted --
      # the constant name provides documentation. UUIDs inside `T.let` wrappers
      # where the parent is a constant assignment are also accepted.
      #
      # @example
      #
      #   # bad — inline UUID as method argument
      #   Source::Record.find_by(id: '018cef8e-3278-7c72-a7b1-84c4bb2f3733')
      #
      #   # good — extracted to a named constant
      #   DEFAULT_SOURCE_ID = '018cef8e-3278-7c72-a7b1-84c4bb2f3733'.freeze
      #   Source::Record.find_by(id: DEFAULT_SOURCE_ID)
      #
      #   # good — constant with T.let type annotation
      #   SOURCE_ID = T.let('018d05e5-e6eb-77ec-a019-b440b43d4a35', String)
      #
      class HardcodedUuidInSource < Base
        MSG = 'Extract hardcoded UUID to a named constant with a comment identifying the record.'

        # Matches standard UUID v4/v7 format: 8-4-4-4-12 lowercase hex digits.
        UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

        def on_str(node)
          return unless uuid_literal?(node)
          return if assigned_to_constant?(node)

          add_offense(node)
        end

        private

        # The string value matches a UUID. Guard against binary string content
        # (e.g., embedded image data in test fixtures) which raises
        # Encoding::CompatibilityError on regex match.
        def uuid_literal?(node)
          value = node.value
          return false unless value.valid_encoding?

          UUID_PATTERN.match?(value)
        end

        # The string is the RHS (directly or via T.let/.freeze) of a constant assignment.
        # Constant assignments provide a name that documents the UUID's purpose.
        def assigned_to_constant?(node)
          parent = node.parent
          return true if parent&.casgn_type?

          return false unless parent&.send_type?

          # Handle `CONST = 'uuid'.freeze` — grandparent is casgn
          if parent.method_name == :freeze
            grandparent = parent.parent
            return true if grandparent&.casgn_type?
          end

          # Handle `CONST = T.let('uuid', String)` — grandparent is casgn
          if parent.method_name == :let
            grandparent = parent.parent
            return true if grandparent&.casgn_type?
          end

          false
        end
      end
    end
  end
end
