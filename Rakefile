# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/**/*_test.rb'
end

task default: :test

Dir[File.join(__dir__, 'lib/tasks/**/*.rake')].each { |file| load file }
