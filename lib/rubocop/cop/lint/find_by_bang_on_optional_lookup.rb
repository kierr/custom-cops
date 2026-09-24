# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `find_by!` in consumers, jobs, and services where the lookup
      # key originates from external or optional data (API responses, parsed
      # JSON, optional associations, batch-processed identifiers). `find_by!`
      # raises `ActiveRecord::RecordNotFound`, producing 500 crashes for
      # lookups that legitimately return nil.
      #
      # Controllers are excluded because `find_by!` is correct there — a
      # missing record warrants a 404 response. `create_or_find_by!` is
      # excluded because it always creates the record if missing.
      #
      # The heuristic is directory-based: flag `find_by!` only in
      # `app/consumers/`, `app/jobs/`, and `app/services/`. These layers
      # process external or batch data where the lookup target may not exist.
      #
      # @example
      #
      #   # bad — crashes on unknown postcode (geo API response data)
      #   address.zip = Geo::Zip.find_by!(code: address.components['postcode'])
      #
      #   # bad — crashes if source was deleted between batches
      #   @source = Source.find_by!(id: '018cef8e-...')
      #
      #   # good — returns nil, caller handles absence
      #   address.zip = Geo::Zip.find_by(code: address.components['postcode'])
      #
      #   # good — controllers: 404 is the correct response
      #   WorldObject.find_by!(object_id: params[:object_id])
      #
      #   # good — always creates if missing
      #   Source.create_or_find_by!(name: 'FastPeopleSearch')
      class FindByBangOnOptionalLookup < Base
        MSG = 'Use `find_by` instead of `find_by!` in %<layer>s — the lookup target may not exist. Handle nil explicitly.'

        BANG_METHODS = %i[find_by!].freeze

        # Directories where find_by! on optional data is likely a bug.
        # Consumers process Kafka messages, jobs run asynchronously,
        # services handle business logic — all deal with external data.
        OPTIONAL_LAYERS = { 'app/consumers/' => 'consumers', 'app/jobs/' => 'jobs',
                            'app/services/' => 'services' }.freeze

        def on_send(node)
          return unless BANG_METHODS.include?(node.method_name)
          return if create_or_find_by?(node)

          layer = optional_layer_for_file(processed_source.file_path)
          return unless layer

          add_offense(node.loc.selector, message: format(MSG, layer: layer))
        end

        private

        def create_or_find_by?(node)
          method_name = node.method_name.to_s
          method_name.start_with?('create_or_find_by', 'find_or_create_by')
        end

        def optional_layer_for_file(filepath)
          OPTIONAL_LAYERS.each do |dir, label|
            return label if filepath.include?(dir)
          end
          nil
        end
      end
    end
  end
end
