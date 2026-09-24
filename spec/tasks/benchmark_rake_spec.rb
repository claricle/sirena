# frozen_string_literal: true

require "spec_helper"
require "rake"
require "open3"
require "tmpdir"
require "fileutils"

# spec_helper.rb already requires "sirena" process-wide, so an in-process load of
# tasks/benchmark.rake can never reproduce the NoMethodError this guards against --
# shell out to a fresh `ruby` process instead, loading only what the real Rakefile
# loads before `tasks/*.rake` (a bare Sirena module via lib/sirena/version.rb).
#
module BareSirenaModuleHelper
  def run_against_bare_sirena_module(repo_root, ruby_after_load)
    script = <<~RUBY
      require 'rake'
      require_relative 'lib/sirena/version'
      load 'tasks/benchmark.rake'
      #{ruby_after_load}
    RUBY
    Open3.capture3("ruby", "-I", "lib", "-e", script, chdir: repo_root)
  end
end

# Puts a fake executable named `name` at the front of PATH for the duration of the
# block, so any `system("<name> ...")` call in the code under test resolves to it
# instead of the real tool. Used to simulate mmdc (or, with name: "ruby", the
# subprocess Sirena's own startup benchmark shells out to) failing without
# depending on the real tool's actual availability on the machine running specs.
module FakeExecutableHelper
  def with_fake_executable(name, exit_code: 1)
    Dir.mktmpdir do |dir|
      script_path = File.join(dir, name)
      File.write(script_path, "#!/bin/sh\nexit #{exit_code}\n")
      FileUtils.chmod("+x", script_path)

      original_path = ENV.fetch("PATH", nil)
      ENV["PATH"] = "#{dir}:#{original_path}"
      begin
        yield
      ensure
        ENV["PATH"] = original_path
      end
    end
  end
end

# rubocop:disable RSpec/DescribeClass -- no single class to describe (whole rake
# namespace + PerformanceBenchmarker); same shape as spec/tasks/coverage_rake_spec.rb.
RSpec.describe "tasks/benchmark.rake" do
  include BareSirenaModuleHelper
  include FakeExecutableHelper

  let(:repo_root) { File.expand_path("../..", __dir__) }

  it "lets PerformanceBenchmarker call Sirena.render after only the gemspec-style load (regression for the NoMethodError)" do
    _out, err, status = run_against_bare_sirena_module(
      repo_root, "puts Sirena.render(\"graph TD\\nA-->B\").class"
    )

    expect(status).to be_success, "expected success, got:\n#{err}"
    expect(err).not_to include("NoMethodError")
  end

  it "fails the same way this bug used to, if the require is removed (mutation control)" do
    source = File.read(File.join(repo_root, "tasks/benchmark.rake"))
    without_require = source.sub("require 'sirena'\n", "")
    expect(without_require).not_to eq(source) # sanity: the substitution actually matched

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "tasks"))
      File.write(File.join(dir, "tasks/benchmark.rake"), without_require)
      FileUtils.ln_s(File.join(repo_root, "lib"), File.join(dir, "lib"))

      script = <<~RUBY
        require 'rake'
        require_relative 'lib/sirena/version'
        load 'tasks/benchmark.rake'
        Sirena.render("graph TD\\nA-->B")
      RUBY
      _out, err, status = Open3.capture3("ruby", "-I", "lib", "-e", script, chdir: dir)

      expect(status).not_to be_success
      expect(err).to include("NoMethodError")
    end
  end

  describe "#speedup_label" do
    subject(:benchmarker) { PerformanceBenchmarker.new }

    # PerformanceBenchmarker is defined once tasks/benchmark.rake is loaded; loading it
    # twice in this process (spec_helper already required 'sirena', so the load-order bug
    # above doesn't apply here) would redefine the class harmlessly, but Rake tasks can
    # only be defined once per Rake::Application -- load in a fresh one.
    around do |example|
      original_application = Rake.application
      Rake.application = Rake::Application.new
      load File.expand_path("../../tasks/benchmark.rake", __dir__)
      example.run
    ensure
      Rake.application = original_application
    end

    it "labels a ratio at or above 1 as faster, using the ratio directly" do
      expect(benchmarker.send(:speedup_label, 2.0)).to eq("2.0x faster")
      expect(benchmarker.send(:speedup_label, 1.0)).to eq("1.0x faster")
    end

    it "labels a ratio below 1 as slower, using the inverted ratio (not the raw fraction)" do
      expect(benchmarker.send(:speedup_label, 0.5)).to eq("2.0x slower")
      expect(benchmarker.send(:speedup_label, 0.25)).to eq("4.0x slower")
    end
  end

  describe "#benchmark_memory_usage" do
    around do |example|
      original_application = Rake.application
      Rake.application = Rake::Application.new
      load File.expand_path("../../tasks/benchmark.rake", __dir__)
      example.run
    ensure
      Rake.application = original_application
    end

    it "reports no numbers, only that nothing was measured -- no hardcoded estimate" do
      fake_available = Class.new(PerformanceBenchmarker) do
        def mermaid_cli_available?
          true
        end
      end

      result = fake_available.new.send(:benchmark_memory_usage)

      expect(result.keys).to eq([:note])
      expect(result[:note]).to eq("Memory usage was not measured in this run")
    end
  end

  describe "mmdc failure handling" do
    around do |example|
      original_application = Rake.application
      Rake.application = Rake::Application.new
      load File.expand_path("../../tasks/benchmark.rake", __dir__)
      example.run
    ensure
      Rake.application = original_application
    end

    it "reports no mermaid timing for a single render when every mmdc invocation fails" do
      with_fake_executable("mmdc") do
        result = PerformanceBenchmarker.new.send(:benchmark_single_renders)

        expect(result).not_to be_empty
        expect(result.values.map { |data| data[:mermaid_time] }).to all(be_nil)
      end
    end

    it "omits mermaid_total from a batch render when every mmdc invocation fails" do
      with_fake_executable("mmdc") do
        result = PerformanceBenchmarker.new.send(:benchmark_batch_renders)

        expect(result[:sirena_total]).not_to be_nil
        expect(result).not_to have_key(:mermaid_total)
        expect(result).not_to have_key(:mermaid_per_diagram)
      end
    end

    it "generates a report from a failed batch without raising (regression for the nil-division crash)" do
      benchmarker = PerformanceBenchmarker.new
      results = {
        system_info: {
          ruby_version: "0", platform: "x", sirena_version: "0",
          mermaid_cli_version: "unknown", cpu_info: "x", timestamp: Time.now.iso8601
        },
        single_diagram: { flowchart: { sirena_time: 0.01, mermaid_time: nil } },
        batch_rendering: { diagram_count: 50, sirena_total: 0.5, sirena_per_diagram: 0.01 },
        memory_usage: {},
        startup_time: { sirena: 0.5, mermaid: nil }
      }

      report = nil
      expect { report = benchmarker.send(:generate_report, results) }.not_to raise_error
      expect(report).to include("not measured")
    end

    it "raises if the Sirena subprocess itself fails (not an external-tool flake)" do
      with_fake_executable("ruby") do
        expect { PerformanceBenchmarker.new.send(:benchmark_startup_time) }
          .to raise_error(/Sirena subprocess startup benchmark failed/)
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
