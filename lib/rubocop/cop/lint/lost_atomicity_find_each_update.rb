# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects `find_each { |r| r.update(...) }` and `find_each { |r| r.save }`
      # in jobs and services where `update_all` should be used instead. Row-by-row
      # updates lose atomicity — individual row failures leave partial state, and
      # callbacks fire per row rather than once as a set operation.
      #
      # Only flags code in `app/jobs/` and `app/services/`. Per-row processing in
      # controllers, models, or other contexts may be intentional.
      #
      # Cannot safely autocorrect — replacing with `update_all` requires understanding
      # which columns are being set and whether callbacks are intentionally skipped.
      #
      # @example
      #
      #   # bad — row-by-row update in a job loses atomicity
      #   Person::Entity.where(id: ids).find_each { |e| e.update(processed: true) }
      #
      #   # bad — save inside find_each block
      #   scope.find_each { |alert| alert.update!(is_active: false) }
      #
      #   # good — atomic set operation
      #   Person::Entity.where(id: ids).update_all(processed: true)
      #
      #   # good — find_each with non-mutating work (no offense)
      #   scope.find_each { |record| process(record) }
      #
      #   # good — find_each in a controller (not flagged)
      #   records.find_each { |r| r.update(status: :done) }
      class LostAtomicityFindEachUpdate < Base
        MSG = 'Row-by-row `update` inside `find_each` is non-atomic: a failure ' \
              'mid-batch leaves partial state. A set operation (`update_all`) is ' \
              'atomic but skips callbacks/validations — choose deliberately.'

        UPDATE_METHODS = %i[update update!].freeze
        SAVE_METHODS = %i[save save!].freeze

        # Matches `find_each` with a block where the block body calls
        # `update`, `update!`, `save`, or `save!` on the block parameter.
        def_node_matcher :find_each_with_mutation?, <<~PATTERN
          (block
            (send _ :find_each ...)
            (args (arg $_))
            $_)
        PATTERN

        def on_block(node)
          return unless in_target_directory?
          return unless node.method_name == :find_each

          match = find_each_with_mutation?(node)
          return unless match

          block_param, = match
          body = node.body
          return unless body

          return unless mutates_block_param?(body, block_param)

          add_offense(node.loc.begin)
        end

        private

        # Only flag code in jobs and services — per-row processing in
        # controllers, models, or other contexts may be intentional.
        def in_target_directory?
          path = processed_source.file_path
          path.include?('app/jobs/') || path.include?('app/services/') || path.include?('app/models/concerns/')
        end

        # Whether the block body calls update/save on the block parameter
        # anywhere in its subtree. A full subtree walk catches mutations
        # inside any container (if/case/while/begin/rescue/nested block)
        # and the receiver_matches? helper unwraps T.cast / T.let, so the
        # old per-container-type descent is unnecessary.
        def mutates_block_param?(body, param_name)
          return false unless body.is_a?(RuboCop::AST::Node)

          body.each_node(:send).any? do |send_node|
            mutation_send?(send_node, param_name)
          end

          def mutation_send?(node, param_name)
            return false unless node&.send_type?

            method_name = node.method_name
            return false unless UPDATE_METHODS.include?(method_name) || SAVE_METHODS.include?(method_name)

            receiver = node.receiver
            return false unless receiver

            receiver_matches?(receiver, param_name)
          end

          # The receiver might be the block param directly, or wrapped in
          # a Sorbet cast: `T.cast(e, SomeType).update(...)` or `T.let(e, ApplicationRecord).update(...)`.
          def receiver_matches?(receiver, param_name)
            case receiver.type
            when :lvar
              receiver.name == param_name
            when :send
              # T.cast(bs, Type) or T.let(e, Type)
              # Send node children: [receiver_const, :method_name, first_arg, second_arg]
              if sorbet_cast?(receiver)
                inner = receiver.children[2]
                inner&.lvar_type? && inner.name == param_name
              else
                false
              end
            else
              false
            end
          end

          def sorbet_cast?(node)
            return false unless node&.send_type?

            receiver = node.receiver
            return false unless receiver&.const_type?

            receiver.source == 'T' && %i[cast let].include?(node.method_name)
          end
        end
      end
    end
  end
end
