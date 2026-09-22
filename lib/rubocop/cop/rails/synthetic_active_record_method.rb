# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Detects synthetic ActiveRecord method calls built via string interpolation,
      # such as `record.send("#{field}_blank?")`. These methods do not exist on
      # ActiveRecord — `blank?` is an ActiveSupport predicate on the returned value,
      # not a dynamic attribute predicate on the record itself.
      #
      # The correct form is `record.send(field).blank?`, which reads the attribute
      # value and then applies the ActiveSupport query method.
      #
      # @example
      #
      #   # bad — constructs a method name that does not exist on ActiveRecord
      #   record.send("#{field}_blank?")
      #   record.send("#{column}_present?")
      #   record.send("#{attr}_nil?")
      #
      #   # good — reads the attribute, then applies the predicate on the value
      #   record.send(field).blank?
      #   record.send(column).present?
      #   record.send(attr).nil?
      class SyntheticActiveRecordMethod < Base
        MSG = 'Avoid synthetic ActiveRecord methods via string interpolation. ' \
              "Use `record.send(field).blank?` instead of `record.send(\"#\{field}_blank?\")`."

        # ActiveSupport query methods that are value-level, not record-level.
        # These exist on the attribute value returned by `send`, not as dynamic
        # methods on the record itself.
        VALUE_PREDICATES = %w[blank? present? nil? empty?].freeze

        # Matches: send("#{<anything>}_blank?"), send("#{<anything>}_present?"), etc.
        # The pattern matches a :send call where the first argument is a dstr (interpolated
        # string) ending with one of the known value predicates.
        def_node_matcher :synthetic_predicate_send?, <<~PATTERN
          (send _ :send
            (dstr ... (str #value_predicate_suffix?)))
        PATTERN

        def on_send(node)
          return unless synthetic_predicate_send?(node)

          add_offense(node)
        end

        private

        # Predicate for def_node_matcher: receives the captured value from (str ...)
        # which is the string content (e.g., "_blank?"), not the AST node.
        def value_predicate_suffix?(str_value)
          VALUE_PREDICATES.any? { |pred| str_value.end_with?(pred) }
        end
      end
    end
  end
end
