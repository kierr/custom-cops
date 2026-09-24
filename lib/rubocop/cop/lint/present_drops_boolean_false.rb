# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `.present?` used as a guard on values that may be boolean `false`.
      # `present?` returns `false` for both `nil` and `false`, silently discarding
      # legitimate `false` values. When the guarded expression carries boolean
      # semantics, `present?` is the wrong check — use `!x.nil?` or `x != false` instead.
      #
      # Flagged when the receiver of `.present?` indicates boolean domain:
      # - Method names ending in `?` (Ruby predicate convention)
      # - Method/variable names containing boolean indicator words as whole-word
      #   segments (underscore-delimited): active, enabled, verified, confirmed,
      #   valid, flag, paid, closed
      # - Boolean prefix names: is_, has_, can_, should_, will_, was_, does_
      # - Sorbet sig on the receiver method declaring T::Boolean return
      #
      # @example
      #
      #   # bad — predicate method returns boolean, present? drops false
      #   do_thing if user.verified?.present?
      #
      #   # bad — method name contains "enabled" as a whole word segment
      #   do_thing if account.is_enabled.present?
      #
      #   # bad — sorbet sig declares T::Boolean return
      #   sig { returns(T.nilable(T::Boolean)) }
      #   def feature_enabled?
      #     @enabled
      #   end
      #   do_thing if feature_enabled?.present?
      #
      #   # bad — variable name starts with boolean prefix
      #   result[:x] = is_active if is_active.present?
      #
      #   # good — explicit nil check preserves false
      #   do_thing if !user.verified?.nil?
      #
      #   # good — string domain, present? is appropriate
      #   name = params[:name] if params[:name].present?
      #
      #   # good — collection presence check
      #   process(items) if items.present?
      #
      class PresentDropsBooleanFalse < Base
        extend AutoCorrector

        MSG = '`.present?` drops boolean `false` — use `!%<receiver>s.nil?` when `false` is a valid value.'

        PREDICATE_SUFFIX = '?'

        # Boolean indicator words that must match as whole underscore-delimited
        # segments in method/variable names. "valid" in "last_validated_at" does NOT
        # match because the segment is "validated", not "valid".
        BOOLEAN_WORD_SEGMENTS = %w[active enabled verified confirmed valid flag paid closed].freeze

        # Prefixes that strongly indicate boolean when they start a name.
        BOOLEAN_PREFIXES = %w[is_ has_ can_ should_ will_ was_ does_].freeze

        # Suffixes that strongly indicate a non-boolean value even when a boolean
        # prefix is present. "can_receive_updated_at" has can_ prefix but _at suffix
        # means it is a timestamp.
        NON_BOOLEAN_SUFFIXES = %w[_at _on _date _id _count _name _url _token].freeze

        def_node_matcher :present_call?, <<~PATTERN
          (send $_ :present?)
        PATTERN

        def on_send(node)
          receiver = present_call?(node)
          return unless receiver
          return if rationale?(node)
          return unless boolean_domain?(receiver)
          return unless in_guard_context?(node)

          add_offense(node, message: format(MSG, receiver: receiver.source)) do |corrector|
            corrector.replace(node.loc.expression, "!#{receiver.source}.nil?")
          end
        end

        private

        # Per-instance exemption: a RATIONALE comment within 5 lines above
        # the .present? call suppresses the offense. Legitimate when the
        # receiver is boolean but false genuinely means "not present" in the
        # domain (e.g. a tri-state coerced to truthy).
        def rationale?(node)
          return false unless node.loc.expression

          node_line = node.loc.expression.line
          processed_source.comments.any? do |comment|
            comment_line = comment.loc.expression.line
            comment_line >= node_line - 5 && comment_line < node_line &&
              comment.text.include?('RATIONALE')
          end
        end

        # Determines whether the receiver of `.present?` carries boolean semantics.
        def boolean_domain?(receiver)
          case receiver.type
          when :send
            method_name = receiver.method_name.to_s
            return true if method_name.end_with?(PREDICATE_SUFFIX)
            return true if boolean_name?(method_name)
            return true if receiver_sig_returns_boolean?(receiver)
          when :lvar
            name = receiver.name.to_s
            return true if name.end_with?(PREDICATE_SUFFIX)
            return true if boolean_name?(name)
          end

          false
        end

        # Checks whether a name (method or variable) contains boolean indicator
        # words as whole underscore-delimited segments, or starts with a boolean prefix.
        # "is_enabled" matches (is_ prefix). "last_validated_at" does NOT match
        # because the segment is "validated", not "valid". "can_receive_updated_at"
        # does NOT match because it ends in _at (timestamp).
        def boolean_name?(name)
          return false if NON_BOOLEAN_SUFFIXES.any? { |suf| name.end_with?(suf) }
          return true if BOOLEAN_PREFIXES.any? { |prefix| name.start_with?(prefix) }

          segments = name.tr('?', '_').split('_')
          segments.any? { |seg| BOOLEAN_WORD_SEGMENTS.include?(seg) }
        end

        # Checks the Sorbet sig of the method being called on the receiver.
        # For `user.verified?.present?`, checks whether `verified?` has a sig
        # declaring T::Boolean return. Only checks the *called method's* sig,
        # not the enclosing method's sig.
        def receiver_sig_returns_boolean?(send_node)
          return false unless send_node.send_type?

          method_name = send_node.method_name
          return false if method_name == :present?

          surrounding_method = send_node.each_ancestor(:def).first
          return false unless surrounding_method

          method_def = find_method_in_scope(surrounding_method, method_name)
          return false unless method_def

          sig_node = find_sig_for_method(method_def)
          return false unless sig_node

          sig_returns_boolean?(sig_node)
        end

        # The `.present?` call must appear as a guard condition: in `if`/`unless`,
        # ternary, postfix conditional, or a boolean operator chain feeding a guard.
        def in_guard_context?(present_node)
          parent = present_node.parent
          return false unless parent

          # Postfix conditional: `x = y if y.present?`
          return true if parent.if_type? && parent.modifier_form?

          # `if x.present?` / `unless x.present?` — full conditional form
          return true if parent.if_type? && parent.condition == present_node

          # Ternary: `x.present? ? a : b`
          return true if parent.if_type?

          # Boolean operator in guard: `if x.present? && y`
          return true if parent.or_type? || parent.and_type?

          false
        end

        # Search for a method definition with the given name among siblings
        # in the same scope (class/module body).
        def find_method_in_scope(ref_method, target_name)
          scope = ref_method.parent
          return nil unless scope

          scope.children.each do |child|
            next unless child.def_type?
            next unless child.method_name == target_name

            return child
          end

          nil
        end

        def find_sig_for_method(method_node)
          return nil unless method_node.parent

          siblings = method_node.parent.children
          idx = siblings.index(method_node)
          return nil unless idx&.positive?

          prev_sibling = siblings[idx - 1]
          return prev_sibling if sig_node?(prev_sibling)

          # Sometimes the sig is inside a begin block (e.g., `sig { final ... }`)
          if prev_sibling&.begin_type?
            prev_sibling.children.each do |child|
              return child if sig_node?(child)
            end
          end

          nil
        end

        def sig_node?(node)
          return false unless node&.block_type?

          node.method_name == :sig
        end

        def sig_returns_boolean?(sig_block)
          sig_block.descendants.any? do |descendant|
            next false unless descendant.send_type?
            next false unless descendant.method_name == :returns

            arg = descendant.first_argument
            contains_boolean_type?(arg)
          end
        end

        def contains_boolean_type?(node)
          return false unless node

          node.each_node(:const).any? do |const_node|
            const_node.const_name == 'T::Boolean'
          end
        end
      end
    end
  end
end
