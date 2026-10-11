# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/surface_manifest"

RSpec.describe SurfaceManifest do
  include FakeSurfaceCheckout

  let(:directory) { Dir.mktmpdir("surface-manifest") }
  let(:launcher) { %w[env] }
  let(:cases) do
    [
      { "id" => "good", "source_path" => case_file("g.mmd", "ok") },
      { "id" => "bad", "source_path" => case_file("b.mmd", "bad") },
    ]
  end

  after { FileUtils.remove_entry(directory) }

  def case_file(name, body)
    write_case_file(directory, name, body)
  end

  def record_with(name, **overrides)
    root = build_fake_checkout(File.join(directory, name), **overrides)
    described_class.record(root, cases, launcher: launcher)
  end

  describe ".record" do
    subject(:manifest) { record_with("one") }

    def surface(name, id)
      manifest.fetch("cases").fetch(id).fetch(name)
    end

    it "records the API svg checksum" do
      expect(surface("api", "good")).to eq(
        "svg_sha256" => Digest::SHA256.hexdigest("<svg>ok</svg>"),
      )
    end

    it "records the API error class and text" do
      expect(surface("api", "bad")).to eq(
        "error_class" => "ArgumentError", "error_message" => "boom",
      )
    end

    it "records CLI stdout checksum, stderr text and exit status on success" do
      expect(surface("cli", "good")).to eq(
        "stdout_sha256" => Digest::SHA256.hexdigest("ok"),
        "stderr" => "",
        "exit_status" => 0,
      )
    end

    it "records CLI stderr text and exit status on failure" do
      expect(surface("cli", "bad")).to include("stderr" => "Error: boom\n",
                                               "exit_status" => 1)
    end

    it "replaces the checkout path in recorded text" do
      root_text = File.join(directory, "two")
      manifest = record_with("two", api_error: "in #{root_text}/lib")
      row = manifest.dig("cases", "bad", "api")

      expect(row.fetch("error_message")).to eq("in <ROOT>/lib")
    end
  end

  describe ".checkout_env" do
    around do |example|
      previous = ENV.fetch("BUNDLE_LOCKFILE", nil)
      example.run
    ensure
      ENV["BUNDLE_LOCKFILE"] = previous
    end

    it "points the child at the checkout's own Gemfile, not the caller's" do
      env = described_class.checkout_env("/some/checkout")

      expect(env).to include("BUNDLE_GEMFILE" => "/some/checkout/Gemfile")
    end

    it "unsets the caller's absolute Bundler lockfile" do
      ENV["BUNDLE_LOCKFILE"] = "/caller/Gemfile.lock"

      expect(described_class.checkout_env("/some/checkout"))
        .to include("BUNDLE_LOCKFILE" => nil)
    end
  end

  describe ".scrub" do
    it "normalizes newlines and masks checkout paths and object addresses" do
      text = "/r/lib: #<Position:0x0000000123cf3540>\r\n"

      expect(described_class.scrub(text, "/r"))
        .to eq("<ROOT>/lib: #<Position:0xADDR>\n")
    end
  end

  describe ".compare" do
    let(:baseline) { record_with("before") }

    it "reports nothing for two identical checkouts" do
      expect(described_class.compare(baseline, record_with("after"))).to eq([])
    end

    {
      "api_svg" => ["good", { svg_suffix: "!" }],
      "api_error" => ["bad", { api_error: "different" }],
      "cli_stdout" => ["good", { cli_out_suffix: "\n" }],
      "cli_stderr" => ["bad", { cli_err: "Error: other" }],
      "cli_exit" => ["bad", { cli_exit: 2 }],
    }.each do |surface, (case_id, change)|
      it "names the case and the #{surface} surface when only it differs" do
        after = record_with("after", **change)
        found = described_class.compare(baseline, after)

        expect(found.map { |d| [d["case"], d["surface"]] })
          .to eq([[case_id, surface]])
      end
    end

    it "reports a case present on one side only" do
      shrunk = { "cases" => baseline.fetch("cases").slice("good") }

      expect(described_class.compare(baseline, shrunk))
        .to eq([{ "case" => "bad", "surface" => "case_set",
                  "before" => true, "after" => false }])
    end
  end

  describe ".run" do
    subject(:outcome) do
      described_class.run(["compare", write_manifest("before", baseline),
                           write_manifest("after", changed)])
    end

    let(:baseline) { record_with("a") }
    let(:changed) { record_with("b", cli_exit: 3) }

    def write_manifest(name, manifest)
      File.join(directory, "#{name}.json").tap do |path|
        File.write(path, JSON.generate(manifest))
      end
    end

    it "exits unsuccessfully from compare" do
      expect(outcome.last).to be(false)
    end

    it "names the differing surface" do
      expect(outcome.first.first)
        .to start_with("DIFFERS bad [cli_exit]: 1 -> 3")
    end

    it "rejects a wrong argument count" do
      expect { described_class.run(%w[compare only-one]) }
        .to raise_error(described_class::ManifestError, /usage/)
    end
  end

  describe ".sample_paths" do
    subject(:first) { described_class.sample_paths(directory, 3) }

    before do
      %w[a b c d e f].each do |name|
        case_file("#{name}.txt", "x")
        FileUtils.mkdir_p(File.join(directory, name))
        File.write(File.join(directory, name, "1.mmd"), "x")
      end
    end

    it "is deterministic" do
      expect(first).to eq(described_class.sample_paths(directory, 3))
    end

    it "is spread across the sorted corpus" do
      expect(first.map { |p| File.basename(File.dirname(p)) }).to eq(%w[a c e])
    end
  end

  describe ".run_process" do
    subject(:run_process) do
      described_class.run_process(["env"], chdir: directory, timeout: 1)
    end

    before do
      allow(Gem).to receive(:win_platform?).and_return(true)
      allow(Open3).to receive(:popen3)
    end

    it "does not request a POSIX process group on Windows" do
      run_process

      expect(Open3).to have_received(:popen3)
        .with(instance_of(Hash), "env", chdir: directory)
    end
  end
end
