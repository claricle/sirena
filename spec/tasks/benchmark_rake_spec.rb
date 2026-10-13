# frozen_string_literal: true

require "spec_helper"
require "rake"
require "open3"
require "tmpdir"
require "fileutils"

# spec_helper.rb already requires "sirena" process-wide, so an in-process load
# of tasks/benchmark.rake cannot reproduce the NoMethodError guarded here.
# Shell out to a fresh `ruby` process instead, loading only what the real
# Rakefile loads before `tasks/*.rake` (a bare Sirena module via
# lib/sirena/version.rb).
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

# Puts a fake executable named `name` at the front of PATH for the duration of
# the block, so any `system("<name> ...")` call in the code under test finds it
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
# namespace + PerformanceBenchmarker); same shape as
# spec/tasks/coverage_rake_spec.rb.
RSpec.describe "tasks/benchmark.rake", :aggregate_failures do
  include BareSirenaModuleHelper
  include FakeExecutableHelper

  let(:repo_root) { File.expand_path("../..", __dir__) }

  it "lets PerformanceBenchmarker call Sirena.render after only the " \
     "gemspec-style load (regression for the NoMethodError)" do
    _out, err, status = run_against_bare_sirena_module(
      repo_root, "puts Sirena.render(\"graph TD\\nA-->B\").class"
    )

    expect(status).to be_success, "expected success, got:\n#{err}"
    expect(err).not_to include("NoMethodError")
  end

  context "with the Sirena require removed" do
    let(:source) { File.read(File.join(repo_root, "tasks/benchmark.rake")) }
    let(:without_require) { source.sub("require \"sirena\"\n", "") }
    let(:mutation_result) do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "tasks"))
        File.write(File.join(dir, "tasks/benchmark.rake"), without_require)
        FileUtils.ln_s(File.join(repo_root, "lib"), File.join(dir, "lib"))
        run_against_bare_sirena_module(dir, 'Sirena.render("graph TD\\nA-->B")')
      end
    end

    it "actually removes the require from the source" do
      expect(without_require).not_to eq(source)
    end

    it "fails the same way as the original load-order bug" do
      _out, err, status = mutation_result
      expect(status).not_to be_success
      expect(err).to include("NoMethodError")
    end
  end

  describe "#speedup_label" do
    subject(:benchmarker) { PerformanceBenchmarker.new }

    # PerformanceBenchmarker is defined once tasks/benchmark.rake is loaded.
    # Loading it twice in this process (spec_helper already required 'sirena',
    # so the load-order bug above does not apply here) would redefine the class
    # harmlessly, but Rake tasks can only be defined once per
    # Rake::Application -- load in a fresh one.
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

    it "labels a ratio below 1 as slower, using the inverted ratio " \
       "(not the raw fraction)" do
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

    let(:available_benchmarker) do
      Class.new(PerformanceBenchmarker) do
        def mermaid_cli_available?
          true
        end
      end.new
    end
    let(:memory_usage) { available_benchmarker.send(:benchmark_memory_usage) }

    it "reports no numbers, only that nothing was measured -- " \
       "no hardcoded estimate" do
      expect(memory_usage.keys).to eq([:note])
      expect(memory_usage[:note])
        .to eq("Memory usage was not measured in this run")
    end
  end

  describe "mmdc failure handling" do
    # with_fake_executable writes a #!/bin/sh script and relies on PATH-based
    # lookup to shadow a real executable -- Windows has neither shebang
    # execution nor bare-name PATH resolution the same way, so a fake "ruby"
    # or "mmdc" placed at the front of PATH does not shadow the real one; it
    # instead breaks Ruby's OWN subsequent subprocess calls (observed on CI:
    # "The system cannot find the path specified" repeated for unrelated
    # system() calls after the fake executable is installed). Same convention
    # as spec/scripts/hardened_mmdc_spec.rb and
    # spec/scripts/mermaid_diff_spec.rb.
    before { skip("the harness is POSIX-only") if Gem.win_platform? }

    around do |example|
      original_application = Rake.application
      Rake.application = Rake::Application.new
      load File.expand_path("../../tasks/benchmark.rake", __dir__)
      example.run
    ensure
      Rake.application = original_application
    end

    let(:failed_batch_results) do
      {
        system_info: {
          ruby_version: "0", platform: "x", sirena_version: "0",
          mermaid_cli_version: "unknown",
          cpu_info: "x",
          timestamp: Time.now.iso8601
        },
        single_diagram: { flowchart: { sirena_time: 0.01, mermaid_time: nil } },
        batch_rendering: {
          diagram_count: 50,
          sirena_total: 0.5,
          sirena_per_diagram: 0.01,
        },
        memory_usage: {},
        startup_time: { sirena: 0.5, mermaid: nil },
      }
    end

    let(:single_results) do
      with_fake_executable("mmdc") do
        PerformanceBenchmarker.new.send(:benchmark_single_renders)
      end
    end

    let(:batch_results) do
      with_fake_executable("mmdc") do
        PerformanceBenchmarker.new.send(:benchmark_batch_renders)
      end
    end

    it "reports no mermaid timing for a single render when every mmdc " \
       "invocation fails" do
      expect(single_results).not_to be_empty
      expect(single_results.values.map { |data| data[:mermaid_time] })
        .to all(be_nil)
    end

    it "omits mermaid_total from a batch render when every mmdc " \
       "invocation fails" do
      expect(batch_results[:sirena_total]).not_to be_nil
      expect(batch_results).not_to have_key(:mermaid_total)
      expect(batch_results).not_to have_key(:mermaid_per_diagram)
    end

    it "generates a report from a failed batch without raising " \
       "(regression for the nil-division crash)" do
      expect do
        PerformanceBenchmarker.new.send(:generate_report, failed_batch_results)
      end.not_to raise_error
    end

    it "marks absent timings in the failed batch report as not measured" do
      report = PerformanceBenchmarker.new.send(:generate_report,
                                               failed_batch_results)
      expect(report).to include("not measured")
    end

    it "raises if the Sirena subprocess itself fails " \
       "(not an external-tool flake)" do
      with_fake_executable("ruby") do
        expect { PerformanceBenchmarker.new.send(:benchmark_startup_time) }
          .to raise_error(/Sirena subprocess startup benchmark failed/)
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
