# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `find_by!` and `.find` (with non-integer arguments) in consumers
      # and jobs. These layers process external data (Kafka messages, enqueued
      # payloads) where the record may not exist when the code runs. A
      # `RecordNotFound` exception crashes the consumer/job without DLQ routing
      # and may cause permanent failure when retry is disabled or exhausted.
      #
      # This cop supersedes `FindByBangInJob` (jobs only) and
      # `FindByBangOnOptionalLookup` (jobs + consumers + services) by combining
      # their scope into a single cop that covers `app/consumers/` and
      # `app/jobs/` regardless of method nesting depth.
      #
      # Excluded patterns:
      # - `create_or_find_by!` / `find_or_create_by!` (always creates the record)
      # - `find_by!` preceded by a `# Required:` comment (the record is genuinely
      #   expected and its absence warrants a crash)
      # - `find_by!` inside a `rescue ActiveRecord::RecordNotUnique` block (the
      #   record was just created by a concurrent process)
      # - `.find` with integer arguments (trusted internal primary keys)
      # - `.find` with a block (Enumerable#find, not ActiveRecord)
      #
      # @example
      #
      #   # bad — crashes permanently if record was deleted between enqueue and perform
      #   source = Source.find_by!(id: external_id)
      #
      #   # bad — .find with a string/external argument crashes on missing record
      #   capture = Document::Capture.find(external_uuid)
      #
      #   # good — returns nil, caller handles absence
      #   source = Source.find_by(id: external_id)
      #
      #   # good — Required: comment marks this as intentional
      #   # Required: source must exist for this job to be meaningful
      #   source = Source.find_by!(id: source_id)
      #
      #   # good — not in a consumer/job directory
      #   Source.find_by!(id: id) # in app/controllers/...
      #
      #   # good — integer primary key from trusted internal source
      #   record = Person.find(42)
      #
      class FindByBangInConsumerOrJob < Base
        MSG = 'Avoid `%<method>s` in %<layer>s — the record may not exist. ' \
              'Use the non-bang variant and handle nil, or add a `# Required:` comment if the record is mandatory.'

        BANG_METHODS = %i[find_by!].freeze
        FIND_METHODS = %i[find].freeze

        # Directories where bang finders are likely a bug.
        TARGET_DIRECTORIES = { 'app/consumers/' => 'consumers', 'app/jobs/' => 'jobs' }.freeze

        def on_send(node)
          return unless in_target_directory?
          return unless bang_finder?(node) || find_with_string_arg?(node)
          return if create_or_find_by_variant?(node)
          return if preceded_by_required_comment?(node)
          return if inside_record_not_unique_rescue?(node)

          layer = layer_for_file(processed_source.file_path)
          # layer is guaranteed non-nil because in_target_directory? already confirmed a match.
          add_offense(node.loc.selector, message: format(MSG, method: node.method_name, layer: layer))
        end

        private

        def in_target_directory?
          filepath = processed_source.file_path
          TARGET_DIRECTORIES.keys.any? { |dir| filepath.include?(dir) }
        end

        def layer_for_file(filepath)
          TARGET_DIRECTORIES.each do |dir, label|
            return label if filepath.include?(dir)
          end
          nil
        end

        def bang_finder?(node)
          return false unless node.send_type?

          BANG_METHODS.include?(node.method_name)
        end

        def find_with_string_arg?(node)
          return false unless node.send_type?
          return false unless FIND_METHODS.include?(node.method_name)
          # .find with a block is Enumerable#find, not ActiveRecord
          return false if node.block_node
          # .find with no arguments is not a meaningful finder
          return false if node.arguments.empty?

          # Only flag when the argument looks like a string/interpolated/external value.
          # Integer arguments are likely primary keys from trusted internal sources.
          node.arguments.any? { |arg| string_like?(arg) }
        end

        def string_like?(node)
          return false if t_cast_to_integer?(node)

          node.str_type? || node.dstr_type? || node.send_type?
        end

        # T.cast(expr, Integer) narrows to Integer at runtime — the result is
        # a trusted primary key, not an untrusted string/external value.
        def t_cast_to_integer?(node)
          return false unless node.send_type?
          return false unless node.method_name == :cast

          receiver = node.receiver
          return false unless receiver&.const_type? && receiver.source == 'T'

          type_arg = node.arguments.last
          type_arg&.const_type? && type_arg.source == 'Integer'
        end

        def create_or_find_by_variant?(node)
          method_name = node.method_name.to_s
          method_name.start_with?('create_or_find_by', 'find_or_create_by')
        end

        def preceded_by_required_comment?(node)
          line = node.location.selector.line
          source_lines = processed_source.lines

          (line - 1).downto(1) do |check_line|
            text = source_lines[check_line - 1].to_s.strip
            break unless text.start_with?('#')

            return true if text.match?(/\A#\s*Required:/i)
          end

          false
        end

        def inside_record_not_unique_rescue?(node)
          node.each_ancestor(:resbody).any? do |resbody|
            rescue_classes = resbody.exceptions
            rescue_classes.any? do |exc|
              next false unless exc.const_type?

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
