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
      { "id" => "good", "source_path" => write_case_file(directory, "g.mmd", "ok") },
      { "id" => "bad", "source_path" => write_case_file(directory, "b.mmd", "bad") },
    ]
  end

  after { FileUtils.remove_entry(directory) }

  def record_with(name, **overrides)
    root = build_fake_checkout(File.join(directory, name), **overrides)
    described_class.record(root, cases, launcher: launcher)
  end

  describe ".record" do
    subject(:manifest) { record_with("one") }

    it "records the API svg checksum and the API error text" do
      api = manifest.fetch("cases").transform_values { |row| row.fetch("api") }

      expect(api.fetch("good")).to eq(
        "svg_sha256" => Digest::SHA256.hexdigest("<svg>ok</svg>"),
      )
      expect(api.fetch("bad")).to eq(
        "error_class" => "ArgumentError", "error_message" => "boom",
      )
    end

    it "records CLI stdout checksum, stderr text and exit status" do
      cli = manifest.fetch("cases").transform_values { |row| row.fetch("cli") }

      expect(cli.fetch("good")).to eq(
        "stdout_sha256" => Digest::SHA256.hexdigest("ok"),
        "stderr" => "",
        "exit_status" => 0,
      )
      expect(cli.fetch("bad")).to include("stderr" => "Error: boom\n",
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
    it "points the child at the checkout's own Gemfile, not the caller's" do
      env = described_class.checkout_env("/some/checkout")

      expect(env).to include("BUNDLE_GEMFILE" => "/some/checkout/Gemfile")
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
        found = described_class.compare(baseline, record_with("after", **change))

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
    it "exits unsuccessfully from compare and names the differing surface" do
      before_path = File.join(directory, "before.json")
      after_path = File.join(directory, "after.json")
      File.write(before_path, JSON.generate(record_with("a")))
      File.write(after_path, JSON.generate(record_with("b", cli_exit: 3)))

      lines, success = described_class.run(["compare", before_path, after_path])

      expect(success).to be(false)
      expect(lines.first).to start_with("DIFFERS bad [cli_exit]: 1 -> 3")
    end

    it "rejects a wrong argument count" do
      expect { described_class.run(%w[compare only-one]) }
        .to raise_error(described_class::ManifestError, /usage/)
    end
  end

  describe ".sample_paths" do
    it "is deterministic and spread across the sorted corpus" do
      %w[a b c d e f].each do |name|
        write_case_file(directory, "#{name}.txt", "x")
        FileUtils.mkdir_p(File.join(directory, name))
        File.write(File.join(directory, name, "1.mmd"), "x")
      end
      first = described_class.sample_paths(directory, 3)

      expect(first).to eq(described_class.sample_paths(directory, 3))
      expect(first.map { |p| File.basename(File.dirname(p)) }).to eq(%w[a c e])
    end
  end
end
