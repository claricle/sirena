# frozen_string_literal: true

require "rake"
require "spec_helper"

module ClaimsManifestRake
  def with_rake_application
    original = Rake.application
    Rake.application = Rake::Application.new
    yield
  ensure
    Rake.application = original
  end

  def task_exit_status
    yield
    0
  rescue SystemExit => e
    e.status
  end

  def invoke_with_report(result)
    with_rake_application do
      load File.expand_path("../../tasks/claims_manifest.rake", __dir__)
      allow(Sirena::ClaimsManifestCheck).to receive(:report!).and_return(result)
      task_exit_status { Rake::Task["claims_manifest:check"].invoke }
    end
  end
end

RSpec.describe ClaimsManifestRake do
  include described_class

  it "fails the task when the manifest report is not clean" do
    expect(invoke_with_report(false)).not_to eq(0)
  end

  it "passes the task when the manifest report is clean" do
    expect(invoke_with_report(true)).to eq(0)
  end

  it "wires the check into the default rake task" do
    with_rake_application do
      load File.expand_path("../../Rakefile", __dir__)

      prerequisites = Rake::Task[:default].prerequisites
      expect(prerequisites).to include("claims_manifest:check")
    end
  end
end
