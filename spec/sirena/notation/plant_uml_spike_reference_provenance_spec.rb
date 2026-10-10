# frozen_string_literal: true

require "digest"
require "spec_helper"
require "yaml"

RSpec.describe YAML do
  let(:spike_dir) { File.expand_path("../../plantuml_spike", __dir__) }
  let(:provenance) { described_class.load_file(File.join(spike_dir, "provenance.yml")) }
  let(:cases) { provenance.fetch("cases") }

  def names(dir, extension)
    Dir[File.join(dir, "*.#{extension}")].map { |path| File.basename(path, ".#{extension}") }
  end

  def digest_for(dir, name, extension)
    Digest::SHA256.file(File.join(dir, "#{name}.#{extension}")).hexdigest
  end

  def hashes_match?(dir, manifest)
    manifest.all? do |name, row|
      row == {
        "source_sha256" => digest_for(File.join(dir, "cases"), name, "puml"),
        "reference_sha256" => digest_for(File.join(dir, "references"), name, "svg"),
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
    expect(names(File.join(spike_dir, "cases"), "puml"))
      .to match_array(names(File.join(spike_dir, "references"), "svg")).and match_array(cases.keys)
    expect(hashes_match?(spike_dir, cases)).to be(true)
  end
end
