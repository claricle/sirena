# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:root) { File.expand_path("../../../../plantuml/sequence", __dir__) }
  let(:scenes) do
    case_ids.map do |id|
      source = File.read(Dir["#{root}/*#{id}--*.puml"].first)
      parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
      parsed.transform.new.call(parsed.diagram)
    end
  end

  context "with sequential and parallel frames" do
    let(:case_ids) { %w[altpar_003 altpar_004 altpar_008] }
    let(:shaft_ys) do
      scenes.map do |scene|
        scene.arrows.map { |arrow| arrow.path[/M \S+ (\S+)/, 1].to_f.round(3) }
      end
    end
    let(:expected) do
      common = [102.109, 102.109, 176.731, 176.731,
                251.352, 311.617, 251.352, 311.617]
      [common, common, [102.109, 176.731, 176.731]]
    end

    it "matches the pinned altpar_003/004/008 frame and branch cadence" do
      expect(shaft_ys).to eq(expected)
    end
  end

  context "with nested frames and a parallel self message" do
    let(:case_ids) { %w[altpar_001 altpar_002 altpar_005 altpar_007] }
    let(:frame_tops) do
      scenes.map do |scene|
        scene.fragments.map { |frame| frame.y.round(3) }.sort
      end
    end
    let(:expected) do
      [[77.299, 108.609], [77.299], [73.299, 104.609], [77.299, 108.609]]
    end

    it "matches the pinned altpar_001/002/005/007 frame contact positions" do
      expect(frame_tops).to eq(expected)
    end
  end

  context "with self messages before and after parallel frames" do
    let(:case_ids) { %w[altpar_001 altpar_002 altpar_005 altpar_007] }
    let(:offsets) do
      scenes.map do |scene|
        arrow = scene.arrows.find do |item|
          item.texts.first.content.start_with?("test")
        end
        scene.fragments.map(&:y).min - arrow.path[/M \S+ (\S+)/, 1].to_f
      end
    end

    it "aligns the self contact two and a half pixels below its shaft" do
      expect(offsets).to all(be_within(0.0001).of(2.5))
    end
  end
end
