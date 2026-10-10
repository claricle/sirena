# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../../scripts/ci_baseline"

RSpec.describe CiBaseline, :aggregate_failures do
  let(:root) { Dir.mktmpdir("ci-baseline") }
  let(:repo) { SeededCiRepo.new(root) }
  let(:shas) { repo.shas }

  # The checkout of the feature branch with everything fetched.
  let(:feature_checkout) { repo.checkout("work", branch: "feature") }

  after { FileUtils.remove_entry(root) }

  def pr_payload(base_ref: "main", head_repo: "o/r", base_repo: "o/r")
    { "pull_request" => {
      "base" => { "ref" => base_ref, "repo" => { "full_name" => base_repo } },
      "head" => { "ref" => "feature", "repo" => { "full_name" => head_repo } },
    } }
  end

  def shallow_checkout
    shallow = repo.checkout("shallow", branch: "feature", depth: 1)
    repo.git(shallow, "fetch", "--quiet", "--depth", "1", "origin",
             "main:refs/remotes/origin/main")
    shallow
  end

  describe "pull_request" do
    it "is the merge-base with the PR base ref, not the moved base tip" do
      result = described_class.resolve("pull_request", pr_payload,
                                       dir: feature_checkout)

      expect(result.sha).to eq(shas[:m2])
      expect(result.sha).not_to eq(shas[:m3])
      expect(result.mode).to eq("pull_request")
    end

    it "fails on a one-commit shallow checkout, naming the missing history" do
      expect do
        described_class.resolve("pull_request", pr_payload, dir: shallow_checkout)
      end.to raise_error(described_class::Error, /fetch more history/)
    end

    it "resolves once the shallow checkout is deepened" do
      shallow = shallow_checkout
      repo.git(shallow, "fetch", "--quiet", "--unshallow", "origin")
      repo.git(shallow, "fetch", "--quiet", "origin",
               "main:refs/remotes/origin/main")

      result = described_class.resolve("pull_request", pr_payload, dir: shallow)

      expect(result.sha).to eq(shas[:m2])
    end

    it "needs a base ref in the payload" do
      expect do
        described_class.resolve("pull_request", {}, dir: feature_checkout)
      end.to raise_error(described_class::Error, /base\.ref/)
    end
  end

  describe "pull_request from a fork" do
    it "names the base ref from the payload, not the default branch" do
      payload = pr_payload(base_ref: "release", head_repo: "fork/r")
      result = described_class.resolve("pull_request", payload,
                                       dir: feature_checkout)

      expect(result.sha).to eq(shas[:m1])
      expect(result.mode).to eq("fork_pull_request")
    end
  end

  describe "push" do
    it "is the event's before commit" do
      payload = { "before" => shas[:f1] }

      result = described_class.resolve("push", payload, dir: feature_checkout)

      expect(result.sha).to eq(shas[:f1])
      expect(result.mode).to eq("push")
    end

    it "falls back to the default-branch merge-base for a new branch" do
      payload = { "before" => CiBaseline::ZERO_SHA,
                  "repository" => { "default_branch" => "main" } }

      result = described_class.resolve("push", payload, dir: feature_checkout)

      expect(result.sha).to eq(shas[:m2])
      expect(result.mode).to eq("push_new_branch")
    end

    it "falls back the same way when a force-push dropped before" do
      payload = { "before" => "1" * 40,
                  "repository" => { "default_branch" => "main" } }

      result = described_class.resolve("push", payload, dir: feature_checkout)

      expect(result.sha).to eq(shas[:m2])
      expect(result.mode).to eq("push_new_branch")
    end

    it "is consistency-only for a new branch with no default branch known" do
      payload = { "before" => CiBaseline::ZERO_SHA }

      result = described_class.resolve("push", payload, dir: feature_checkout)

      expect(result).to be_consistency_only
    end
  end

  describe "merge_group" do
    it "is merge_group.base_sha" do
      payload = { "merge_group" => { "base_sha" => shas[:m3] } }

      result = described_class.resolve("merge_group", payload,
                                       dir: feature_checkout)

      expect(result.sha).to eq(shas[:m3])
      expect(result.mode).to eq("merge_group")
    end

    it "fails when base_sha is not fetched" do
      payload = { "merge_group" => { "base_sha" => "2" * 40 } }

      expect do
        described_class.resolve("merge_group", payload, dir: feature_checkout)
      end.to raise_error(described_class::Error, /not fetched/)
    end
  end

  describe "workflow_dispatch and schedule" do
    it "uses the explicit baseline_sha input" do
      payload = { "inputs" => { "baseline_sha" => shas[:f1] } }

      result = described_class.resolve("workflow_dispatch", payload,
                                       dir: feature_checkout)

      expect(result.sha).to eq(shas[:f1])
    end

    it "is consistency-only for a dispatch without the input" do
      result = described_class.resolve("workflow_dispatch", {},
                                       dir: feature_checkout)

      expect(result).to be_consistency_only
    end

    it "is consistency-only for the nightly schedule" do
      result = described_class.resolve("schedule", {}, dir: feature_checkout)

      expect(result).to be_consistency_only
    end

    it "fails on an explicit baseline that is not a commit" do
      payload = { "inputs" => { "baseline_sha" => "--upload-pack=x" } }

      expect do
        described_class.resolve("workflow_dispatch", payload,
                                dir: feature_checkout)
      end.to raise_error(described_class::Error, /not a commit/)
    end
  end

  it "refuses an event it has no rule for" do
    expect { described_class.resolve("issues", {}, dir: feature_checkout) }
      .to raise_error(described_class::Error, /no baseline rule/)
  end

  describe "as CI runs it" do
    def run(payload)
      script = File.expand_path("../../scripts/ci_baseline.rb", __dir__)
      event_path = File.join(root, "event.json")
      File.write(event_path, JSON.generate(payload))
      Open3.capture3({ "GITHUB_EVENT_NAME" => "pull_request",
                       "GITHUB_EVENT_PATH" => event_path },
                     RbConfig.ruby, script, chdir: feature_checkout)
    end

    it "reads the event file and prints the baseline" do
      out, _err, status = run(pr_payload)

      expect(status).to be_success
      expect(out).to eq("baseline=#{shas[:m2]}\nmode=pull_request\n")
    end

    it "exits non-zero with a message on a resolution error" do
      _out, err, status = run({})

      expect(status).not_to be_success
      expect(err).to include("base.ref")
    end
  end
end
