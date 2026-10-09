# frozen_string_literal: true

require "spec_helper"
require "yaml"

module LicenseTruth
  ROOT = File.expand_path("../..", __dir__)
  IDENTIFIER = "BSD-2-Clause"
  README = File.join(ROOT, "README.adoc")
  DOCS_INDEX = File.join(ROOT, "docs/index.adoc")
  DOCS_CONFIG = File.join(ROOT, "docs/_config.yml")
  LICENSE = File.join(ROOT, "LICENSE")
  GEMSPEC = File.join(ROOT, "sirena.gemspec")

  module_function

  def gem_license
    Gem::Specification.load(GEMSPEC).license
  end

  def public_declarations
    config = YAML.safe_load_file(DOCS_CONFIG)
    [
      File.read(README),
      File.read(DOCS_INDEX),
      config.fetch("footer_content"),
    ]
  end
end

RSpec.describe LicenseTruth do
  it "matches the gem metadata to the repository license" do
    facts = [
      described_class.gem_license,
      File.foreach(described_class::LICENSE).first.chomp,
    ]

    expect(facts).to eq(["BSD-2-Clause", "BSD 2-Clause License"])
  end

  it "names BSD-2-Clause consistently in the public documentation" do
    declarations = described_class.public_declarations
    identifiers = declarations.map do |source|
      source.scan(described_class::IDENTIFIER)
    end

    expect(identifiers).to all(include(described_class::IDENTIFIER))
  end

  it "does not publish the superseded MIT or BSD-3-Clause claims" do
    source = described_class.public_declarations.join("\n")

    expect(source).not_to match(/MIT License|BSD-3(?: |-)Clause/i)
  end
end
