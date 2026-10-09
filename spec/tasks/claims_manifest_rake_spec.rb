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
end

RSpec.describe ClaimsManifestRake do
  include described_class

  it "fails the task when the manifest report is not clean" do
    with_rake_application do
      load File.expand_path("../../tasks/claims_manifest.rake", __dir__)
      allow(Sirena::ClaimsManifestCheck).to receive(:report!).and_return(false)

      status = task_exit_status { Rake::Task["claims_manifest:check"].invoke }
      expect(status).not_to eq(0)
    end
  end

  it "passes the task when the manifest report is clean" do
    with_rake_application do
      load File.expand_path("../../tasks/claims_manifest.rake", __dir__)
      allow(Sirena::ClaimsManifestCheck).to receive(:report!).and_return(true)

      status = task_exit_status { Rake::Task["claims_manifest:check"].invoke }
      expect(status).to eq(0)
    end
  end

  it "wires the check into the default rake task" do
    with_rake_application do
      load File.expand_path("../../Rakefile", __dir__)

      prerequisites = Rake::Task[:default].prerequisites
      expect(prerequisites).to include("claims_manifest:check")
    end
  end
end
