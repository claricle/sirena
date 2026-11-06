# frozen_string_literal: true

require "nokogiri"
require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"
  include DejaVuText

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:root) { File.expand_path("../../../../plantuml", __dir__) }

  context "with one boxed participant" do
    let(:case_id) do
      "resources.vega.nonreg.group2791.self_message_solo--9d48b2180ff0"
    end
    let(:source) do
      File.read(File.join(root, "sequence", "#{case_id}.puml"))
    end
    let(:reference) do
      path = File.join(root, "references", "sequence", "#{case_id}.svg")
      Nokogiri::XML(File.read(path)).remove_namespaces!
    end
    let(:scene) do
      parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
      parsed.transform.new.call(parsed.diagram)
    end

    it "sizes the intrinsic head to its label plus the pinned padding" do
      expect(scene.heads.first.width)
        .to be_within(1e-9).of(dejavu("a", size: 14) + 14.0)
    end

    it "uses the pinned intrinsic head height" do
      reference_head = reference.at_xpath('//g[@id="part1-head"]/rect')
      expect(scene.heads.first.height).to eq(reference_head["height"].to_f)
    end

    it "leaves the title width to the box" do
      title = dejavu("Box A", size: 13, bold: true)
      expect(scene.frames.first.width).to be_within(1e-9).of(title + 6.0)
    end

    it "centers the box on its head" do
      head = scene.heads.first
      frame = scene.frames.first
      expect(frame.x + (frame.width / 2)).to be_within(1e-9)
        .of(head.x + (head.width / 2))
    end
  end

  context "when a boxed participant was first mentioned with an external" do
    let(:case_id) do
      "resources.vega.nonreg.group2791." \
        "box_between_external_participants--7d1d5500d228"
    end
    let(:source) do
      File.read(File.join(root, "sequence", "#{case_id}.puml"))
    end
    let(:scene) do
      parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
      parsed.transform.new.call(parsed.diagram)
    end
    let(:parity_row) do
      reference_path = File.join(
        root, "references", "sequence", "#{case_id}.svg"
      )
      result = SpecSupport::LayoutParity::CaseComparator.compare(
        case_id: "plantuml/sequence/#{case_id}",
        type: "plantuml_sequence", reference: reference_path,
        reference_svg: File.read(reference_path),
        sirena_svg: Sirena.render(source, notation: :plantuml),
        reproduce: __FILE__,
        recognizer: SpecSupport::LayoutParity::PlantumlSequenceRecognizer.new,
        spatial_kinds: [:participant]
      )
      SpecSupport::LayoutParity::CaseLedger.build([result]).first
    end

    it "places the external before the redeclared box member" do
      path = File.join(root, "references", "sequence", "#{case_id}.svg")
      heads = Nokogiri::XML(File.read(path)).remove_namespaces!
        .xpath('//g[contains(@class,"participant-head")]')
      expect(scene.heads.first(scene.lifelines.size).map(&:id))
        .to eq(heads.map { |group| group["data-qualified-name"] })
    end

    it "keeps the center error inside the parity bar without losing elements" do
      expect([
               parity_row.dig("summary", "hard_failure"),
               parity_row.dig("geometry", "matched"),
               parity_row.dig("summary", "metrics", "worst_e_c") <= 0.08,
             ]).to eq([false, 7, true])
    end
  end
end
