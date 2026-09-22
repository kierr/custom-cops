# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Sorbet
      # Detects parameter name mismatches between a Sorbet `sig` block and its
      # method definition. Sorbet does not enforce parameter name matching, so a
      # mismatch causes a silent `ArgumentError` at runtime.
      #
      # The cop matches parameter names, treating underscore-prefixed names as
      # equivalent to their bare form (e.g., `_source` in the def matches `source`
      # in the sig). Both keyword and positional args are checked since Sorbet's
      # `params()` matches both by name.
      #
      # @example Mismatch between sig and def
      #
      #   # bad — `source` in sig doesn't match `_source` in def;
      #   #        `error:`, `classification:`, `payload:` missing from sig
      #   sig { params(run: Run, source: String).void }
      #   def handle_error(run:, error:, classification:, payload:, _source:)
      #
      #   # good — all keyword names match
      #   sig { params(run: Run, error: String, classification: String,
      #                payload: T::Hash, _source: String).void }
      #   def handle_error(run:, error:, classification:, payload:, _source:)
      #
      class SigParamNameMatchesDef < Base
        MSG = 'Sig parameter `%<sig_name>s` does not match any argument in `def`.'

        # Matches a `sig { ... }` block.
        def_node_matcher :sig_block?, <<~PATTERN
          (block (send nil? :sig) ...)
        PATTERN

        # Matches `params(...)` call inside a sig block.
        def_node_matcher :params_call?, <<~PATTERN
          (send nil? :params ...)
        PATTERN

        def on_def(node)
          _ = check_sig_param_names(node)
        end

        def on_defs(node)
          on_def(node)
        end

        private

        def check_sig_param_names(def_node)
          sig = last_sig_before(def_node)
          return unless sig

          sig_entries = extract_sig_entries(sig)
          return unless sig_entries

          # Anonymous params (&, *, **) allow any sig name — skip the entire check.
          return if has_anonymous_args?(def_node)

          def_arg_names = extract_def_arg_names(def_node)

          # Build a normalised set for matching: strip leading underscore.
          def_normalised = def_arg_names.each_with_object({}) do |name, map|
            normalised = name.to_s.delete_prefix('_').to_sym
            map[normalised] = name
          end

          sig_entries.each do |(sig_name, pair_node)|
            normalised = sig_name.to_s.delete_prefix('_').to_sym
            next if def_normalised.key?(normalised)

            key_node = pair_node.children.first
            add_offense(key_node.loc.expression, message: format(MSG, sig_name: sig_name))
          end
        end

        def has_anonymous_args?(def_node)
          def_node.arguments.any? do |arg|
            arg.forward_arg_type? ||
              (arg.blockarg_type? && arg.name.nil?) ||
              (arg.restarg_type? && arg.name.nil?) ||
              (arg.kwrestarg_type? && arg.name.nil?)
          end
        end

        # Find the sig block immediately preceding the def node.
        # Only matches when the sig is the direct predecessor — a sig from a
        # different method further up does NOT count.
        def last_sig_before(def_node)
          parent = def_node.parent
          return nil unless parent&.begin_type?

          siblings = parent.children
          idx = siblings.index(def_node)
          return nil unless idx&.positive?

          prev = siblings[idx - 1]
          sig_block?(prev) ? prev : nil
        end

        # Extract keyword names and their pair nodes from `params(run: Run, error: String)`
        # inside the sig block. Returns nil when no params call is found.
        # Each entry is [symbol_name, pair_node].
        def extract_sig_entries(sig_block)
          body = sig_block.body
          return nil unless body

          # Walk the method chain: `params(...).returns(...).void` etc.
          node = body
          node = node.receiver while node&.send_type? && node.method_name != :params
          return nil unless params_call?(node)

          hash_arg = node.arguments.first
          return nil unless hash_arg&.hash_type?

          hash_arg.children.each_with_object([]) do |pair, entries|
            # Only collect symbol-keyed pairs; skip keyword splats (`**rest`).
            next unless pair.pair_type?

            key = pair.children.first
            entries << [key.value, pair] if key&.sym_type?
          end
        end

        # Extract argument names from the def node. Includes keyword args (kwarg,
        # kwoptarg), positional args (arg, optarg), block args (blockarg), rest
        # args (restarg), and keyword rest args (kwrestarg) since Sorbet's
        # `params()` names all of these by their bare name.
        def extract_def_arg_names(def_node)
          def_node.arguments.each_with_object([]) do |arg, names|
            case arg.type
            when :arg, :optarg, :kwarg, :kwoptarg, :blockarg, :restarg, :kwrestarg
              names << arg.name
            end
          end
        end
      end
    end
  end
end
