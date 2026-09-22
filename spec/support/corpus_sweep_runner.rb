# frozen_string_literal: true

require "open3"
require "rbconfig"

# Runs scripts/corpus_sweep.rb over the pie corpus in a child process with
# Sirena::Engine#render replaced by one fixed string, so the script's own
# pass predicate is what is under test rather than any renderer.
module CorpusSweepRunner
  REPO_ROOT = File.expand_path("../..", __dir__)

  STUB = <<~RUBY
    require "bundler/setup"
    require "sirena"
    Sirena::Engine.class_eval { def render(_source, *) = ENV.fetch("FAKE_SVG") }
    ARGV.replace(["pie"])
    # corpus_sweep.rb only runs its report when loaded as the main program
    # ($PROGRAM_NAME == __FILE__); `load` alone leaves $PROGRAM_NAME as "-e"
    # and the script returns before printing anything.
    $PROGRAM_NAME = File.expand_path("scripts/corpus_sweep.rb")
    load "scripts/corpus_sweep.rb"
  RUBY

  def sweep_totals_for(svg)
    # bundler/setup must run before "sirena" is required in the child, or a
    # default gem (json) activates unpinned and Bundler's own activation
    # later conflicts with the Gemfile's pinned version.
    out, err, status = Open3.capture3({ "FAKE_SVG" => svg }, RbConfig.ruby, "-I", "lib", "-e", STUB, chdir: REPO_ROOT)
    raise "sweep did not run: #{err}" unless status.success?

    passed, total = out.match(%r{^TOTAL: (\d+)/(\d+)}).captures.map(&:to_i)
    { passed: passed, total: total }
  end
end
