# frozen_string_literal: true

require_relative "../../scripts/mermaid_toolchain"

RSpec.describe MermaidToolchain do
  let(:expected) do
    { "node" => "22.23.1", "npm" => "10.9.8", "mmdc" => "11.12.0",
      "mermaid" => "11.16.1", "puppeteer" => "23.11.1",
      "chromium" => "131.0.6778.204",
      "font" => { "package" => "@fontsource/noto-sans", "version" => "5.3.0",
                  "integrity" => "sha512-font", "family" => "Noto Sans",
                  "files" => { "regular.woff2" => "abc" } } }
  end
  let(:changed) { expected.merge("mermaid" => "11.17.0") }

  before do
    described_class.instance_variable_set(:@checked, nil)
    allow(described_class).to receive(:provenance).and_return(expected)
  end

  it "accepts an exact resolved toolchain" do
    allow(described_class).to receive(:resolved_provenance).and_return(expected)

    expect(described_class.verify_toolchain).to eq(expected)
  end

  it "fails when a resolved dependency drifts" do
    allow(described_class).to receive(:resolved_provenance).and_return(changed)

    expect { described_class.verify_toolchain }
      .to raise_error(described_class::DriftError,
                      /mermaid: expected "11\.16\.1", got "11\.17\.0"/)
  end

  it "uses repository-local mmdc with pinned configuration" do
    allow(described_class).to receive(:resolved_provenance).and_return(expected)

    expect(described_class.command("-i", "in.mmd", "-o", "out.svg"))
      .to eq(expected_command)
  end

  it "adds the no-sandbox config only for the requested CI canary" do
    enable_ci_browser_config

    expect(described_class.command)
      .to include("--puppeteerConfigFile",
                  described_class::CI_PUPPETEER_CONFIG_PATH)
  end

  it "configures Chromium's CI launch without a sandbox" do
    config = JSON.parse(File.read(described_class::CI_PUPPETEER_CONFIG_PATH))

    expect(config.fetch("args"))
      .to contain_exactly("--no-sandbox", "--disable-setuid-sandbox")
  end

  def expected_command
    [
      described_class::MMDC_PATH,
      "--configFile", described_class::CONFIG_PATH,
      "--cssFile", described_class::CSS_PATH,
      "-i", "in.mmd", "-o", "out.svg"
    ]
  end

  def enable_ci_browser_config
    allow(ENV).to receive(:fetch).and_call_original
    stub_ci_canary
    stub_resolved_provenance
  end

  def stub_ci_canary
    allow(ENV).to receive(:fetch)
      .with(described_class::CI_CANARY_ENV, nil).and_return("1")
  end

  def stub_resolved_provenance
    allow(described_class).to receive(:resolved_provenance).and_return(expected)
  end
end
