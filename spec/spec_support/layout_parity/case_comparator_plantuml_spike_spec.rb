# frozen_string_literal: true

require "spec_helper"
require "digest"
require "yaml"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe SpecSupport::LayoutParity::CaseComparator do
  include_context "with an isolated notation registry"

  let(:spike_root) { File.expand_path("../../plantuml_spike", __dir__) }

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def cases
    Dir[File.join(spike_root, "cases", "*.puml")]
  end

  def provenance
    YAML.load_file(File.join(spike_root, "provenance.yml"))
  end

  def case_name(path)
    File.basename(path, ".puml")
  end

  def reference_path(name)
    File.join(spike_root, "references", "#{name}.svg")
  end

  def digest(path)
    Digest::SHA256.file(path).hexdigest if File.file?(path)
  end

  def evidence_failures
    expected = %w[plantuml java graphviz command]
    failures = expected - provenance.fetch("toolchain", {}).keys
    failures + cases.flat_map { |path| case_evidence_failures(path) }
  end

  def case_evidence_failures(path)
    name = case_name(path)
    record = provenance.fetch("cases", {})[name]
    return ["#{name}: missing provenance"] unless record

    reference = reference_path(name)
    hash_failures(name, path, reference, record)
  end

  def hash_failures(name, source, reference, record)
    expected = [record["source_sha256"], record["reference_sha256"]]
    actual = [digest(source), digest(reference)]
    expected.zip(actual).filter_map.with_index do |(wanted, found), index|
      next if wanted == found

      "#{name}: #{%w[source reference][index]} #{found.inspect}"
    end
  end

  def comparison(path)
    name = case_name(path)
    reference = reference_path(name)
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: "plantuml/#{name}", type: "plantuml_class",
      reference: reference, reference_svg: File.read(reference),
      sirena_svg: Sirena.render(File.read(path), notation: :plantuml),
      reproduce: "bundle exec rspec #{__FILE__}",
      recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
      spatial_kinds: [:class]
    )
  end

  def invariant_failures
    cases.filter_map do |path|
      result = comparison(path)
      [case_name(path), result.invariants] if result.hard_failure?
    end
  end

  it "requires complete pinned reference provenance for all 17 cases" do
    expect([cases.size, evidence_failures]).to eq([17, []])
  end

  it "holds the item 14 structural invariants through the public renderer" do
    expect(invariant_failures).to eq([])
  end
end
