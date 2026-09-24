# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `.merge()` calls using symbol keys on JSONB-typed columns.
      # JSONB stores string keys; symbol keys create a separate parallel key.
      # Later access with a string key returns nil, producing silent data-loss
      # bugs that are difficult to diagnose.
      #
      # Receivers flagged:
      #   - bare or chained `metadata` / `structured_data` (unambiguous JSONB
      #     names): `metadata.merge(...)`, `run.metadata.merge(...)`
      #   - chained-only `settings` / `config` / `params` (real JSONB columns
      #     in this schema, but bare use is usually ActionController params or
      #     a config hash): `record.settings.merge(...)`
      #
      # Safe autocorrect converts `key: value` to `'key' => value`.
      #
      # @example
      #
      #   # bad — symbol key on JSONB column
      #   run.metadata.merge(error_class: 'timeout')
      #
      #   # good — string key
      #   run.metadata.merge('error_class' => 'timeout')
      #
      #   # good — plain hash, not a JSONB column
      #   options.merge(timeout: 30)
      #
      #   # good — already using string keys
      #   metadata.merge('retrieval_completed_at' => Time.current.iso8601)
      class SymbolKeyMergeIntoJsonb < Base
        extend AutoCorrector

        MSG = 'Use string keys when merging into a JSONB column. Symbol keys create parallel entries that are inaccessible via string-key lookup.'

        # JSONB-named methods unambiguous enough to flag even when bare
        # (local var or in-model zero-arg accessor). `metadata` and
        # `structured_data` are JSONB columns across many tables in this
        # schema; bare use is typically an in-model column accessor.
        BARE_JSONB_NAMES = %i[metadata structured_data].freeze

        # JSONB-named methods that are also common non-column identifiers
        # (ActionController `params`, config hashes, settings hashes). Real
        # JSONB columns of these names exist in the schema, so they are
        # flagged only when accessed through a receiver (`record.settings`,
        # `model.config`, `run.params`) — the association form is a strong
        # column signal, while the bare form is the false-positive source.
        RECEIVER_REQUIRED_JSONB_NAMES = %i[settings config params].freeze

        # Match any `receiver.merge(...)` call. Argument inspection is done
        # programmatically in on_send rather than in the pattern, because
        # merge accepts variable-arity arguments (hashes and keyword args).
        def_node_matcher :merge_call?, <<~PATTERN
          (send $_ :merge ...)
        PATTERN

        def on_send(node)
          receiver = merge_call?(node)
          return unless receiver
          return unless jsonb_receiver?(receiver)

          symbol_pairs = symbol_keyed_pairs(node)
          return if symbol_pairs.empty?

          symbol_pairs.each do |pair|
            add_offense(pair.key) do |corrector|
              corrector.replace(pair.key.source_range, "'#{pair.key.value}'")
              # The colon separator in `key: value` must become ` =>`.
              # The pair's loc.operator points to `:` in `key:` syntax;
              # replacing it with ` =>` converts to hash-rocket form.
              corrector.replace(pair.loc.operator, ' =>')
            end
          end
        end

        private

        # Collect all symbol-keyed pairs from hash arguments to merge.
        def symbol_keyed_pairs(node)
          node.arguments.each_with_object([]) do |arg, pairs|
            next unless arg.hash_type?

            arg.children.each do |pair|
              next unless pair.pair_type?
              next unless pair.key.sym_type?

              pairs << pair
            end
          end
        end

        # Determine whether the merge receiver looks like a JSONB column.
        # BARE_JSONB_NAMES flag bare or chained; RECEIVER_REQUIRED_JSONB_NAMES
        # flag only the chained (association.column) form. Bare `params` /
        # `config` / `settings` are almost always ActionController params or
        # plain config hashes, not JSONB columns.
        def jsonb_receiver?(node)
          return false unless node.send_type?

          name = node.method_name
          return true if BARE_JSONB_NAMES.include?(name)
          return true if RECEIVER_REQUIRED_JSONB_NAMES.include?(name) && node.receiver

          false
        end
      end
    end
  end
end
