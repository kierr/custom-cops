# typed: ignore
# frozen_string_literal: true

require_relative '../../../../test_helper'

class IvarMutexEagerInitTest < Minitest::Test
  include CopTestHelper

  COP = RuboCop::Cop::Lint::IvarMutexEagerInit

  # --- Bad: offenses expected ---

  def test_flags_mutex_new_in_class_self_body
    offenses = investigate(COP, <<~RUBY)
      module Graph
        class << self
          @mutex = Mutex.new
        end
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/Eagerly initialize/, offenses.first.message)
  end

  OFFENSE_CASES = {
    't_let_mutex_in_module_body' => "module Daemon\n  @mutex = T.let(Mutex.new, Mutex)\nend",
    'monitor_new_in_class_body' => "class Worker\n  @lock = Monitor.new\nend",
    't_let_thread_mutex_in_module_body' => "module Daemon\n  @mutex = T.let(Thread::Mutex.new, Thread::Mutex)\nend",
    'rwlock_in_class_body' => "class Registry\n  @rwlock = Concurrent::ReentrantReadWriteLock.new\nend"
  }.freeze

  OFFENSE_CASES.each do |name, source|
    define_method(:"test_flags_#{name}") do
      offenses = investigate(COP, source)

      assert_equal 1, offenses.size
    end
  end

  def test_flags_thread_mutex_in_module_body
    offenses = investigate(COP, <<~RUBY)
      module Cache
        class << self
          @mutex = Thread::Mutex.new
        end
      end
    RUBY

    assert_equal 1, offenses.size
  end

  # --- Good: no offenses ---

  NO_OFFENSE_CASES = {
    'mutex_init_in_initialize_method' => "class Worker\n  def initialize\n    @mutex = Mutex.new\n  end\nend",
    't_let_mutex_in_initialize_method' => "class Worker\n  def initialize\n    @mutex = T.let(Mutex.new, Mutex)\n  end\nend",
    'mutex_in_class_method_body' => "class Worker\n  def self.setup\n    @mutex = Mutex.new\n  end\nend",
    'semaphore_in_initialize' => "class Pool\n  def initialize(size)\n    @semaphore = Mutex.new\n  end\nend",
    'mutex_in_callback_block' => "class Worker\n  before_action do\n    @mutex = Mutex.new\n  end\nend"
  }.freeze

  NO_OFFENSE_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses
    end
  end

  def test_no_offense_for_lazy_init_with_or_equals
    offenses = investigate(COP, <<~RUBY)
      module Graph
        class << self
          @mutex = T.let(nil, T.nilable(Mutex))
          def mutex
            @mutex ||= Mutex.new
          end
        end
      end
    RUBY

    assert_empty offenses
  end

  NO_OFFENSE_2_CASES = {
    'non_mutex_ivar_in_module_body' => "module Config\n  @settings = {}\nend",
    'non_mutex_class_on_mutex_named_ivar' => "module Foo\n  @mutex = SomeCustomClass.new\nend"
  }.freeze

  NO_OFFENSE_2_CASES.each do |name, source|
    define_method(:"test_no_offense_for_#{name}") do
      offenses = investigate(COP, source)

      assert_empty offenses
    end
  end
end
