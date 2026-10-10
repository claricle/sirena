# frozen_string_literal: true

require "digest"
require "spec_helper"
require "yaml"

RSpec.describe Sirena::Notation::PlantUML do
  let(:spike_dir) { File.expand_path("../../plantuml_spike", __dir__) }
  let(:provenance) do
    YAML.load_file(File.join(spike_dir, "provenance.yml"))
  end
  let(:cases) { provenance.fetch("cases") }

  def names(dir, extension)
    Dir[File.join(dir, "*.#{extension}")].map do |path|
      File.basename(path, ".#{extension}")
    end
  end

  def digest_for(dir, name, extension)
    Digest::SHA256.file(File.join(dir, "#{name}.#{extension}")).hexdigest
  end

  def hashes_match?(dir, manifest)
    manifest.all? do |name, row|
      source = digest_for(File.join(dir, "cases"), name, "puml")
      reference = digest_for(File.join(dir, "references"), name, "svg")
      row == {
        "source_sha256" => source,
        "reference_sha256" => reference,
      }
    end
  end

  it "records the pinned reference toolchain" do
    expect(provenance.fetch("toolchain")).to include(
      "plantuml" => start_with("1.2026.6 "), "java" => "26.0.2",
      "graphviz" => start_with("15.1.1 ")
    )
  end

  it "records one hash-verified reference per spike case" do
    source_names = names(File.join(spike_dir, "cases"), "puml")
    reference_names = names(File.join(spike_dir, "references"), "svg")
    expect(source_names)
      .to match_array(reference_names)
      .and match_array(cases.keys)
  end

  it "matches every recorded reference hash" do
    expect(hashes_match?(spike_dir, cases)).to be(true)
  end
end
