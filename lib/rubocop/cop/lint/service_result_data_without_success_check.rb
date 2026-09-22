# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects accessing `.data` on a ServiceResult without first checking `.success?`
      # or pattern-matching the result. If the ServiceResult is a failure, `.data` is nil
      # and downstream code crashes with NoMethodError.
      #
      # A production crash was caused by checking
      # `is_a?(T.untyped)` instead of `is_a?(ServiceResult)` before accessing `.data`.
      #
      # The cop tracks local variables and instance variables assigned from method calls
      # whose names suggest ServiceResult returns (methods ending in Service, Client,
      # Provider, or containing "fetch", "call", "run"). It flags `.data` access on those
      # variables when no preceding `success?` or `failure?` guard exists in the same
      # method scope, unless the access is inside an `if result.success?` block.
      #
      # @example
      #
      #   # bad — .data accessed without success guard
      #   result = FetchService.call(url: url)
      #   result.data[:items]
      #
      #   # good — explicit success? check before .data access
      #   result = FetchService.call(url: url)
      #   return unless result.success?
      #   result.data[:items]
      #
      #   # good — .data inside if result.success? block
      #   result = FetchService.call(url: url)
      #   if result.success?
      #     process(result.data)
      #   end
      #
      #   # good — T.cast acknowledges the type
      #   result = FetchService.call(url: url)
      #   T.cast(result.data, Hash)
      #
      #   # good — enforce_service_result! raises on failure
      #   result = enforce_service_result!(FetchService.call(url: url), source: 'FetchService')
      #   result.data
      class ServiceResultDataWithoutSuccessCheck < Base
        MSG = 'Accessing `.data` on a ServiceResult without checking `.success?` first. ' \
              'On failure `.data` is nil and downstream code will crash with NoMethodError.'

        # Method name suffixes that indicate a ServiceResult-returning call.
        RESULT_METHOD_SUFFIXES = %w[Service Client Provider Scraper].freeze

        # Method name substrings that indicate a ServiceResult-returning call.
        RESULT_METHOD_SUBSTRINGS = %w[call run fetch execute perform scrape parse search download allocate].freeze

        # Method names that implicitly guard by raising on failure.
        GUARDING_METHODS = %i[enforce_service_result!].freeze

        # The `.data` accessor.
        DATA_METHODS = %i[data].freeze

        # The success/failure check methods.
        SUCCESS_CHECK_METHODS = %i[success? failure?].freeze

        def on_send(node)
          return unless node.method_name == :data
          return unless result_receiver?(node.receiver)

          tracked_name = receiver_name(node.receiver)
          return unless tracked_name

          # If the receiver was assigned via a guarding method, it is safe.
          return if assigned_via_guarding_method?(node, tracked_name)

          # If a T.cast wraps the .data call, the developer acknowledges the type.
          return if t_cast_receiver?(node)

          method_node = find_enclosing_method(node)
          return unless method_node

          # Walk up to find the enclosing conditional that guards this .data access.
          # If we are inside an `if result.success?` (or `unless result.failure?`) block,
          # the access is safe.
          return if guarded_by_success_check?(node, tracked_name)

          # Check whether any prior sibling or ancestor statement checks success.
          return if preceded_by_success_check?(node, tracked_name, method_node)

          add_offense(node.loc.selector)
        end

        private

        # The receiver of `.data` must be an lvar, ivar, or safe-navigation on one.
        def result_receiver?(receiver)
          return false unless receiver

          receiver.lvar_type? || receiver.ivar_type? ||
            (receiver.send_type? && receiver.method_name == :& && result_receiver?(receiver.receiver))
        end

        def receiver_name(receiver)
          return nil unless receiver

          case receiver.type
          when :lvar, :ivar
            receiver.name.to_s
          when :send
            receiver.method_name == :& ? receiver_name(receiver.receiver) : nil
          end
        end

        # Check if the variable was assigned from a call to a known guarding method
        # like `enforce_service_result!`.
        def assigned_via_guarding_method?(data_node, tracked_name)
          method_node = find_enclosing_method(data_node)
          return false unless method_node

          each_assignment(method_node, tracked_name.to_sym).any? do |assign_node|
            assigned_from_guarding_method?(assign_node)
          end
        end

        def assigned_from_guarding_method?(assign_node)
          rhs = assign_node.children[1]
          return false unless rhs&.send_type?

          GUARDING_METHODS.include?(rhs.method_name)
        end

        # Check if the .data call's parent is a T.cast call — the developer is
        # explicitly acknowledging the type via cast.
        def t_cast_receiver?(node)
          parent = node.parent
          return false unless parent&.send_type?
          return false unless parent.method_name == :cast

          receiver = parent.receiver
          receiver&.const_type? && receiver.source == 'T'
        end

        # Walk up the AST to find the enclosing def/defs/block node.
        def find_enclosing_method(node)
          node.each_ancestor(:def, :defs, :block).first
        end

        # Check if the .data access is inside an `if result.success?` or
        # `unless result.failure?` conditional block.
        def guarded_by_success_check?(data_node, tracked_name)
          data_node.each_ancestor(:if).any? do |if_node|
            condition = if_node.condition
            next false unless success_check_on?(condition, tracked_name)

            condition_method = condition.send_type? ? condition.method_name : nil
            # `if result.success?` — data must be in the truthy branch.
            if condition_method == :success?
              truthy_branch = if_node.children[1]
              truthy_branch && node_within?(data_node, truthy_branch)
            # `unless result.failure?` (parsed as `if result.failure?` with nil truthy)
            # or `if result.failure?` — data must be in the falsy branch.
            elsif condition_method == :failure?
              falsy_branch = if_node.children[2]
              falsy_branch && node_within?(data_node, falsy_branch)
            else
              false
            end
          end
        end

        # Check if any statement before the .data access checks success? or failure?
        # on the tracked variable within the same method body.
        def preceded_by_success_check?(data_node, tracked_name, method_node)
          # Collect all lvasgn/ivasgn for this variable to understand control flow.
          # Walk the method body looking for a success? check that precedes data_node
          # and is not inside a conditional that would not guard the data access.
          body = method_body(method_node)
          return false unless body

          find_preceding_success_check(body, data_node, tracked_name)
        end

        def method_body(method_node)
          case method_node.type
          when :def, :defs
            method_node.body
          when :block
            # Block body is the last child after the send and args.
            method_node.children[2..].compact.last
          end
        end

        # Walk the method body linearly, looking for a success? check on the
        # tracked variable that appears before the .data node.
        def find_preceding_success_check(body_node, data_node, tracked_name)
          return false unless body_node

          # If the body is a begin block, walk children linearly.
          if body_node.begin_type?
            children = body_node.children
            data_idx = find_node_index(children, data_node)
            return false unless data_idx

            children[0...data_idx].any? do |sibling|
              checks_success?(sibling, tracked_name)
            end
          else
            # Single-statement body: check if it precedes data_node.
            checks_success?(body_node, tracked_name) && precedes?(body_node, data_node)
          end
        end

        def find_node_index(children, target)
          children.index do |child|
            child.equal?(target) || child.each_descendant.any? { |d| d.equal?(target) }
          end
        end

        # Does this node contain a success? or failure? call on the tracked variable?
        def checks_success?(node, tracked_name)
          node.each_descendant(:send).any? do |send_node|
            success_check_on?(send_node, tracked_name)
          end
        end

        def success_check_on?(condition, tracked_name)
          return false unless condition&.send_type?
          return false unless SUCCESS_CHECK_METHODS.include?(condition.method_name)

          receiver = condition.receiver
          return false unless receiver

          name = receiver_name(receiver)
          name == tracked_name
        end

        # A simple positional check: does `earlier` appear before `later` in source?
        def precedes?(earlier, later)
          earlier.loc.expression.begin_pos < later.loc.expression.begin_pos
        end

        def node_within?(descendant, ancestor)
          return true if descendant.equal?(ancestor)

          descendant.each_ancestor.any? { |a| a.equal?(ancestor) }
        end

        # Yield each assignment to `var_name` within the method body.
        def each_assignment(method_node, var_name)
          return enum_for(:each_assignment, method_node, var_name) unless block_given?

          body = method_body(method_node)
          return unless body

          body.each_descendant(:lvasgn, :ivasgn) do |node|
            yield node if node.children.first == var_name
          end
        end
      end
    end
  end
end
