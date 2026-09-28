# frozen_string_literal: true

require "spec_helper"
require "rake"

# tasks/claims_manifest.rake is loaded only by the Rakefile (`Dir.glob('tasks/**/*.rake')`),
# never required by lib/sirena.rb's require chain -- same convention as
# spec/tasks/corpus_spec.rb's own header comment. Each example gets a fresh
# Rake::Application so re-`load`ing the task file across examples never hits
# Rake's "task already invoked" no-op.
module ClaimsManifestRakeStubs
  # report! returns a boolean rather than exiting itself (see
  # spec/scripts/check_claims_manifest_spec.rb's ".report!" examples) -- this
  # task is the thing that must now convert a `false` into a failed build.
  # check! aborts with SystemExit; returns its status, or 0 if it returns
  # (same helper as spec/tasks/corpus_spec.rb's own CorpusCheckStubs).
  def exit_status_of
    yield
    0
  rescue SystemExit => e
    e.status
  end
end

# rubocop:disable RSpec/DescribeClass -- no single class to describe, task-file
# behavior only; same shape as spec/tasks/benchmark_rake_spec.rb.
RSpec.describe "tasks/claims_manifest.rake" do
  include ClaimsManifestRakeStubs

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path("../../tasks/claims_manifest.rake", __dir__)
    example.run
  ensure
    Rake.application = original_application
  end

  it "aborts (non-zero) when Sirena::ClaimsManifestCheck.report! returns false" do
    allow(Sirena::ClaimsManifestCheck).to receive(:report!).and_return(false)

    expect(exit_status_of { Rake::Task["claims_manifest:check"].invoke }).not_to eq(0)
  end

  it "does not abort when Sirena::ClaimsManifestCheck.report! returns true" do
    allow(Sirena::ClaimsManifestCheck).to receive(:report!).and_return(true)

    expect(exit_status_of { Rake::Task["claims_manifest:check"].invoke }).to eq(0)
  end
end
# rubocop:enable RSpec/DescribeClass
