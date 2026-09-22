# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `find_by!` and `.find` (with string/interpolated arguments) inside
      # job classes. Jobs that crash from `RecordNotFound` may fail permanently when
      # retry is disabled or exhausted — the record may have been deleted between
      # enqueue and perform.
      #
      # Directory-based: only files under `app/jobs/` are flagged. This is where all
      # ActiveJob classes exist in this codebase.
      #
      # Excluded patterns:
      # - `create_or_find_by!` / `find_or_create_by!` (always creates the record)
      # - `find_by!` preceded by a `# Required:` comment (the record is genuinely
      #   expected and its absence warrants a crash)
      # - `find_by!` inside a `rescue ActiveRecord::RecordNotUnique` block (the record
      #   was just created by a concurrent process)
      #
      # @example
      #
      #   # bad — crashes permanently if record was deleted between enqueue and perform
      #   source = Source.find_by!(id: external_id)
      #
      #   # bad — .find with a string/interpolated argument crashes on missing record
      #   capture = Document::Capture.find("uuid-string")
      #
      #   # good — returns nil, caller handles absence
      #   source = Source.find_by(id: external_id)
      #
      #   # good — Required: comment marks this as intentional
      #   # Required: source must exist for this job to be meaningful
      #   source = Source.find_by!(id: source_id)
      #
      #   # good — not in a job directory
      #   Source.find_by!(id: id) # in app/controllers/...
      #
      class FindByBangInJob < Base
        MSG = 'Avoid `%<method>s` in jobs — the record may not exist when the job runs. ' \
              'Use the non-bang variant and handle nil, or add a `# Required:` comment if the record is mandatory.'

        BANG_METHODS = %i[find_by!].freeze
        FIND_METHODS = %i[find].freeze

        def on_send(node)
          return unless in_job_directory?
          return unless bang_finder?(node) || find_with_string_arg?(node)
          return if create_or_find_by_variant?(node)
          return if preceded_by_required_comment?(node)
          return if inside_record_not_unique_rescue?(node)

          add_offense(node.loc.selector, message: format(MSG, method: node.method_name))
        end

        private

        def in_job_directory?
          processed_source.file_path.include?('app/jobs/')
        end

        def bang_finder?(node)
          return false unless node.send_type?

          BANG_METHODS.include?(node.method_name)
        end

        def find_with_string_arg?(node)
          return false unless node.send_type?
          return false unless FIND_METHODS.include?(node.method_name)
          # .find with no arguments is not a finder (e.g., `find` on arrays)
          # .find with a block is Enumerable#find, not ActiveRecord
          return false if node.block_node
          return false if node.arguments.empty?

          # Only flag when the argument looks like a string/interpolated value
          # (UUID, external ID). Integer arguments are likely primary keys from
          # trusted internal sources.
          node.arguments.any? { |arg| string_like?(arg) }
        end

        def string_like?(node)
          node.str_type? || node.dstr_type? || node.send_type?
        end

        def create_or_find_by_variant?(node)
          method_name = node.method_name.to_s
          method_name.start_with?('create_or_find_by', 'find_or_create_by')
        end

        def preceded_by_required_comment?(node)
          # Walk backward through the source to find the nearest preceding comment.
          # A `# Required:` annotation signals that the record genuinely must exist.
          line = node.location.selector.line
          source_lines = processed_source.lines

          # Check comment lines directly above the node, stopping at the first
          # non-comment line or the start of the file.
          (line - 1).downto(1) do |check_line|
            text = source_lines[check_line - 1].to_s.strip
            break unless text.start_with?('#')

            return true if text.match?(/\A#\s*Required:/i)
          end

          false
        end

        def inside_record_not_unique_rescue?(node)
          # When `find_by!` appears inside `rescue ActiveRecord::RecordNotUnique`,
          # the record was just created by a concurrent process — the lookup is
          # guaranteed to succeed. This is a legitimate use of the bang method.
          node.each_ancestor(:resbody).any? do |resbody|
            rescue_classes = resbody.exceptions
            rescue_classes.any? do |exc|
              next false unless exc.const_type?

              # Match ActiveRecord::RecordNotUnique or bare RecordNotUnique
              exc.source.include?('RecordNotUnique')
            end
          rescue NoMethodError
            false
          end
        end
      end
    end
  end
end
