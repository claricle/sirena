# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

# Speed and size checks, held out of `rspec`'s default pattern by their
# file names. They read the clock and build fixtures with thousands of
# boxes, so an ordinary run stays quick and cannot go red because the
# machine was busy. `rake` still runs them, so CI guards every
# regression they pin.
RSpec::Core::RakeTask.new(:benchmark) do |task|
  task.pattern = 'spec/benchmarks/**/*_benchmark.rb'
end

# Load custom rake tasks
Dir.glob('lib/tasks/**/*.rake').each { |r| load r }

task default: [:spec, :benchmark]
