# typed: strict
# frozen_string_literal: true

require_relative '../../custom_cops/comment_window'

module RuboCop
  module Cop
    module Sorbet
      # Flags `case`/`when` blocks where all when clauses reference class/module
      # constants (type-dispatch) and the else branch lacks `T.absurd`. Without
      # `T.absurd`, adding a new union member compiles cleanly, leaving the
      # unhandled case until runtime.
      #
      # @example Guard with T.absurd (no offense)
      #   case item
      #   when Customer::Identification, Vendor::Identification then 'id'
      #   when Customer::Credential, Vendor::Credential then 'cred'
      #   else T.absurd(item)
      #   end
      #
      # @example Missing T.absurd (offense)
      #   case subject
      #   when Customer::Entity then subject.name
      #   when Vendor::Entity then subject.legal_name
      #   end
      #
      # @example Value dispatch (no offense — not type-dispatch)
      #   case status
      #   when :active then process
      #   when :paused then wait
      #   end
      class ExhaustiveUnionDispatch < Base
        include ::RuboCop::Cop::CustomCops::CommentWindow

        MSG = 'Use T.absurd in the else branch when dispatching over union types for exhaustiveness checking, or add # RATIONALE: <reason>.'

        EXCLUDED_PATHS = %w[/adapters/ /controllers/ /consumers/ lib/rubocop/ test/ spec/].freeze

        JUSTIFICATION_PATTERNS = %w[RATIONALE:].freeze

        def_node_matcher :t_absurd_call?, <<~PATTERN
          (send (const nil? :T) :absurd ...)
        PATTERN

        def on_new_investigation
          super
          @file_path = processed_source.file_path.to_s
        end

        def on_case(node)
          return unless app_file?
          return if skip_file?
          return if justified?(node)
          return unless type_dispatch?(node)
          # RATIONALE: T.absurd only proves exhaustiveness for a finite union.
          # Single-branch dispatch and else-less cases have no union to close,
          # so flagging them pushes a semantically wrong T.absurd. Require both
          # multiple const branches and a present else branch.
          return unless node.when_branches.size >= 2
          return unless node.else_branch
          return if else_branch_has_absurd?(node)

          add_offense(node.loc.keyword, message: MSG)
        end

        private

        def app_file?
          @file_path.include?('app/')
        end

        def skip_file?
          EXCLUDED_PATHS.any? { |pattern| @file_path.include?(pattern) }
        end

        # All when conditions are class/module constants (type-dispatch),
        # not strings, symbols, integers, regexps, or other values.
        def type_dispatch?(node)
          branches = node.when_branches
          return false if branches.empty?

          branches.all? do |when_node|
            conditions = when_node.conditions
            next false if conditions.empty?

            conditions.all?(&:const_type?)
          end
        end

        def else_branch_has_absurd?(node)
          return false unless node.else_branch

          else_body = node.else_branch
          nodes = else_body.begin_type? ? else_body.children : [else_body]
          nodes.any? { |n| t_absurd_call?(n) }
        end

        def justified?(node)
          preceding_comments(node).any? do |comment|
            JUSTIFICATION_PATTERNS.any? { |p| comment.text.include?(p) }
          end
        end
      end
    end
  end
end
