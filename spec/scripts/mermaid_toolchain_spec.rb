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

  before do
    described_class.instance_variable_set(:@checked, nil)
    allow(described_class).to receive(:provenance).and_return(expected)
  end

  it "accepts an exact resolved toolchain" do
    allow(described_class).to receive(:resolved_provenance).and_return(expected)

    expect(described_class.check!).to be(true)
  end

  it "fails when a resolved dependency drifts" do
    changed = Marshal.load(Marshal.dump(expected))
    changed["mermaid"] = "11.17.0"
    allow(described_class).to receive(:resolved_provenance).and_return(changed)

    expect { described_class.check! }
      .to raise_error(described_class::DriftError,
                      /mermaid: expected "11\.16\.1", got "11\.17\.0"/)
  end

  it "invokes the repository-local executable with the pinned config and font stylesheet" do
    allow(described_class).to receive(:resolved_provenance).and_return(expected)

    expect(described_class.command("-i", "in.mmd", "-o", "out.svg")).to eq(
      [described_class::MMDC_PATH, "--configFile", described_class::CONFIG_PATH,
       "--cssFile", described_class::CSS_PATH, "-i", "in.mmd", "-o", "out.svg"],
    )
  end
end
