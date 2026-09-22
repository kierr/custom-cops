# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Detects eager initialization of mutex/lock instance variables in class or
      # module bodies. Zeitwerk autoloading can re-evaluate class bodies, niling
      # the instance variable. The lazy-init pattern (`@mutex ||= Mutex.new` via a
      # method) survives re-evaluation because the method re-initializes on next
      # access.
      #
      # A mutex initialization fix shows this caused 6+ broken tests
      # when `@mutex = Mutex.new` in a `class << self` body was nilled by Zeitwerk
      # reload, producing NilError on `@mutex.synchronize`.
      #
      # Only flags assignments in class/module body context — assignments inside
      # `initialize` or other methods are per-instance and safe.
      #
      # @example
      #
      #   # bad — eager init in module body, nilled by Zeitwerk reload
      #   module Graph
      #     class << self
      #       @mutex = Mutex.new
      #     end
      #   end
      #
      #   # bad — eager init in class body
      #   class Worker
      #     @mutex = T.let(Mutex.new, Mutex)
      #   end
      #
      #   # good — lazy init via method
      #   module Graph
      #     class << self
      #       @mutex = T.let(nil, T.nilable(Mutex))
      #       def mutex
      #         @mutex ||= Mutex.new
      #       end
      #     end
      #   end
      #
      #   # good — init inside initialize (per-instance, not affected by Zeitwerk)
      #   class Worker
      #     def initialize
      #       @mutex = Mutex.new
      #     end
      #   end
      class IvarMutexEagerInit < Base
        MSG = 'Eagerly initialize `%<ivar>s` in class/module body instead of lazy init via method. ' \
              'Zeitwerk autoloading can re-evaluate the body, niling the ivar. ' \
              'Use `def mutex; @mutex ||= Mutex.new; end` or equivalent lazy-init pattern.'

        # Ivar names that indicate thread-synchronization state. Suffix match, not an
        # exact-name set: an exact set missed `@us_country_mutex` / `@instance_mutex`
        # while flagging `@mutex` — a gate scoped to a subset of the names
        # the invariant protects gives false confidence on the uncovered rest.
        MUTEX_IVAR_NAME_PATTERN = /\A@(?:\w+_)?(?:mutex|lock|rwlock|monitor|semaphore)\z/

        # Classes whose instantiation indicates a synchronization primitive.
        MUTEX_CLASSES = %w[Mutex Thread::Mutex Monitor ConditionVariable Concurrent::ReentrantReadWriteLock].freeze

        # Matches `T.let(expr, type)` — returns the first argument (the expression).
        def_node_matcher :t_let?, <<~PATTERN
          (send (const {nil? (cbase)} :T) :let $_ ...)
        PATTERN

        def on_ivasgn(node)
          return unless MUTEX_IVAR_NAME_PATTERN.match?(node.name.to_s)
          return if inside_method?(node)
          return if uses_or_equals?(node)

          value_node = node.children.last
          return unless value_node

          # Unwrap T.let(Mutex.new, Mutex) -> Mutex.new
          constructor_node = t_let?(value_node) || value_node
          return unless mutex_constructor?(constructor_node)

          add_offense(node, message: format(MSG, ivar: node.name))
        end

        private

        # Returns true if the node is inside a method definition (def, defs) or a
        # block (e.g., before_action callbacks). Assignments inside these contexts
        # are per-instance or deferred to instance execution, not class-load time.
        def inside_method?(node)
          node.each_ancestor(:def, :defs, :block).any?
        end

        # Returns true if the assignment uses ||= (or-assignment), which is the
        # lazy-init pattern and not a violation.
        def uses_or_equals?(node)
          node.source.include?('||=')
        end

        # Checks whether the constructor call creates a synchronization primitive.
        # Matches `Mutex.new`, `Thread::Mutex.new`, `Monitor.new`, etc.
        def mutex_constructor?(node)
          return false unless node.send_type?
          return false unless node.method_name == :new

          receiver = node.receiver
          return false unless receiver

          class_name = receiver.source
          MUTEX_CLASSES.any? { |klass| class_name == klass || class_name.end_with?("::#{klass}") }
        end
      end
    end
  end
end
