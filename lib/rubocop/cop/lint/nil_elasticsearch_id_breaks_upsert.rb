# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects Elasticsearch `_id:` (or `id:`) assignment from potentially nil
      # hash bracket access in bulk/index/update operations. When `_id` is nil,
      # Elasticsearch auto-generates a random ID, producing unbounded duplicate
      # documents on every upsert instead of updating the existing one.
      #
      # Flags ES bulk entry hashes (`{ index: { ... } }`, `{ update: { ... } }`,
      # `{ delete: { ... } }`) and direct client calls (`.index`, `.bulk`,
      # `.update`) where the `_id` or `id` keyword argument value is a bracket
      # access (`hash['key']` or `hash[:key]`) without a preceding nil guard.
      #
      # Only flags within `app/services/` and `app/consumers/` contexts.
      #
      # @example
      #
      #   # bad — nil _id causes ES to auto-generate, duplicating on every upsert
      #   bulk_body << { update: { _index: 'cases', _id: record['caseNumber'] } }
      #
      #   # bad — same pattern with symbol-keyed hash
      #   bulk_body << { index: { _index: 'profiles', _id: row[:id] } }
      #
      #   # good — nil guard before the ES call
      #   next unless record['caseNumber']
      #   bulk_body << { update: { _index: 'cases', _id: record['caseNumber'] } }
      #
      #   # good — id derived from a method call, not bracket access
      #   bulk_body << { update: { _index: 'cases', _id: result.case_number } }
      #
      #   # good — safe navigation guard
      #   record&.fetch('caseNumber')&.tap do |id|
      #     bulk_body << { update: { _index: 'cases', _id: id } }
      #   end
      #
      class NilElasticsearchIdBreaksUpsert < Base
        MSG = 'ES `_id` from bracket access without nil guard — nil _id causes ' \
              'ES to auto-generate random IDs, producing unbounded duplicates. ' \
              'Add a nil guard (e.g. `next unless %<id_source>s` or an ' \
              '`if %<id_source>s` wrapper) before this call.'

        # ES bulk operation types that accept _id.
        ES_OPERATIONS = %i[index update delete].freeze

        # The hash keys that carry the ES document ID.
        ID_KEYS = %i[_id id].freeze

        def_node_matcher :es_operation_from_hash?, <<~PATTERN
          (hash (pair (sym $_) (hash ...)))
        PATTERN

        # Matches bracket access: hash['key'] or hash[:key]
        def_node_matcher :bracket_access?, <<~PATTERN
          (send $_ {:[] :fetch} ${(str _) (sym _)})
        PATTERN

        def on_hash(node)
          return unless in_services_or_consumers?

          operation = es_operation_from_hash?(node)
          return unless operation
          return unless ES_OPERATIONS.include?(operation)

          inner_hash = find_inner_hash(node, operation)
          return unless inner_hash

          id_pair = find_id_pair(inner_hash)
          return unless id_pair

          id_value = id_pair.value
          receiver, _key = bracket_access?(id_value)
          return unless receiver

          return if guarded?(id_value, node)

          # No autocorrect: the natural fix is `next unless <id>`, but `next`
          # is a LocalJumpError inside a def body (only valid in a block/loop).
          # Whether the enclosing scope is a block or a method is not knowable
          # from the offense alone, so emitting `next` would break method
          # bodies. Let the human pick `next`/`return`/`if` per the message.
          add_offense(id_value, message: format(MSG, id_source: id_value.source))
        end

        private

        # Extract the inner hash from `{ index: { _index: ..., _id: ... } }`.
        def find_inner_hash(outer_hash, operation)
          outer_hash.each_pair do |key_node, value_node|
            next unless key_node.sym_type? && key_node.value == operation

            return value_node if value_node.hash_type?
          end
          nil
        end

        # Find the `_id:` or `id:` pair inside the ES operation hash.
        def find_id_pair(inner_hash)
          inner_hash.each_pair do |key_node, _value_node|
            next unless key_node.sym_type? && ID_KEYS.include?(key_node.value)

            return key_node.parent
          end
          nil
        end

        # Only flag in app/services/ and app/consumers/ to avoid false positives
        # in test files, lib/, and other contexts.
        def in_services_or_consumers?
          filename = processed_source.file_path
          filename.include?('app/services/') || filename.include?('app/consumers/')
        end

        # Check whether the id value is protected by a nil guard in the
        # enclosing scope. Recognizes:
        #   - `next/return unless <id_source>` (and `.present?`/`.presence`
        #     trailing forms) before the ES call
        #   - `next/return if <id_source>.nil?` or `.blank?` before the ES call
        #   - `if <id_source>` / `unless <id_source>.nil?` wrapping the call
        #   - Guards on an intermediate lvar assigned from the id source
        #     (`cn = record['caseNumber']; next unless cn`)
        #   - Safe navigation (`&.`) on the bracket access receiver
        def guarded?(id_value_node, es_hash_node)
          id_source = id_value_node.source

          # Safe navigation on the bracket access itself: record&.fetch('key') or record&.[]
          receiver, = bracket_access?(id_value_node)
          return true if receiver&.csend_type?

          # Check if an enclosing if/unless wraps the ES call with the id as condition.
          # Must be checked before the container search because the wrapping if
          # may be the only ancestor (no begin/block/def in between).
          return true if if_guard_wraps?(es_hash_node, id_source)

          # Check enclosing block/def for a preceding guard.
          # Walk up to the nearest block, begin, or def node.
          container = find_container(es_hash_node)
          return false unless container

          siblings = container_children(container)
          es_idx = siblings.index(es_hash_node) || siblings.index(es_hash_node.parent)
          return false unless es_idx

          prior = siblings[0...es_idx]
          # An intermediate lvar assigned from the id source (`cn = T.cast(
          # record['caseNumber'], ...)`) is a guard target equivalent to the
          # bracket access itself, so `next unless cn` protects the call.
          aliases = alias_lvars(prior, id_source)

          # Search backward through siblings for a guard that references the
          # id source or one of its lvar aliases.
          prior.reverse_each do |sibling|
            return true if guard_references?(sibling, id_source, aliases)
          end

          false
        end

        # lvar names assigned earlier in the same container from an expression
        # containing the id source string. Matches both direct assignment
        # (`cn = record['caseNumber']`) and wrapped forms (`cn = T.cast(
        # record['caseNumber'], ...)`), since both make the lvar a stand-in
        # for the bracket-access value.
        def alias_lvars(prior_siblings, id_source)
          prior_siblings.filter_map do |sibling|
            next unless sibling.lvasgn_type?

            lvar_name, value = sibling.children
            next unless value&.source&.include?(id_source)

            lvar_name
          end
        end

        # Find the nearest container that holds sequential statements.
        def find_container(node)
          node.each_ancestor(:begin, :block, :def, :defs).first
        end

        def container_children(container)
          case container.type
          when :begin
            container.children
          when :block, :def, :defs
            # The body is children[2] for all these node types.
            body = container.children[2]
            if body&.begin_type?
              body.children
            elsif body
              [body]
            else
              []
            end
          else
            []
          end
        end

        # Whether a node is a guard clause that references the id source string
        # or one of its lvar aliases. The `unless` form is intentionally
        # unanchored so trailing truthy checks (`next unless X.present?`) match.
        def guard_references?(node, id_source, aliases = [])
          return false unless node

          alternation = [id_source, *aliases.map(&:to_s)]
                        .map { |s| Regexp.escape(s) }
                        .join('|')
          source = node.source
          # `next unless <id>` / `return unless <id>` (and trailing .present?/.presence)
          return true if source.match?(/\A(next|return)\s+unless\s+(?:#{alternation})/)

          # `next if <id>.nil?` / `return if <id>.nil?`
          return true if source.match?(/\A(next|return)\s+if\s+(?:#{alternation})\.nil\?/)

          # `next if <id>.blank?` / `return if <id>.blank?` (inverse present)
          return true if source.match?(/\A(next|return)\s+if\s+(?:#{alternation})\.blank\?/)

          false
        end

        # Check if an `if <id>` or `unless <id>.nil?` wraps the ES hash node.
        def if_guard_wraps?(es_hash_node, id_source)
          ancestor = es_hash_node.each_ancestor(:if).first
          return false unless ancestor

          condition = ancestor.condition
          cond_source = condition.source

          # `if record['caseNumber']` wrapping the ES call
          return true if cond_source == id_source

          # `unless record['caseNumber'].nil?`
          return true if cond_source.match?(/\A#{Regexp.escape(id_source)}\.nil\?\z/)

          # `if record['caseNumber'].present?` or `unless ...blank?`
          return true if cond_source.match?(/\A#{Regexp.escape(id_source)}\.(?:present|blank)\?\z/)

          false
        end
      end
    end
  end
end
