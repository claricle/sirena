# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::ArrowMarks do
  [[:filled, -1, "->"], [:filled, 1, "<-"],
   [:open, -1, "->>"], [:open, 1, "<<-"]].each do |glyph, inward, token|
    context "with #{token}" do
      let(:reference_heads) do
        path = File.expand_path(
          "../../../../plantuml/references/sequence/" \
          "java.nonreg.simple.SequenceArrows_0001_Test--d918f796209f.svg",
          __dir__,
        )
        doc = Nokogiri::XML(File.read(path)).remove_namespaces!
        shaft = doc.xpath("//text").find { |node| node.text == token }
          .previous_element
        head = shaft.previous_element
        glyph == :open ? [head.previous_element, head] : [head]
      end

      let(:expected_points) do
        line_attributes = %w[x1 y1 x2 y2]
        points = reference_heads.map do |head|
          values = if head.name == "polygon"
                     head["points"].scan(/-?\d+(?:\.\d+)?/)
                   else
                     line_attributes.map { |name| head[name] }
                   end
          values.map { |value| BigDecimal(value) }.each_slice(2).to_a
        end
        tip = glyph == :filled ? points.first[1] : points.first.first
        points.map do |shape|
          shape.map { |x, y| [(x - tip[0]).to_f, (y - tip[1]).to_f] }
        end
      end

      let(:marks) do
        arrow_end = Sirena::Notation::PlantUML::Sequence::ArrowEnd.new(
          glyph: glyph,
        )
        described_class.for(arrow_end, 0, 0, inward).first
      end

      let(:actual_points) do
        marks.map do |mark|
          if mark.kind == "polygon"
            mark.points.scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).to_a
          else
            [[mark.x1, mark.y1], [mark.x2, mark.y2]]
          end
        end
      end

      let(:rendered_heads) do
        source = "@startuml\n!pragma teoz true\n" \
                 "A #{token} B: message\n@enduml\n"
        parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
        scene = parsed.transform.new.call(parsed.diagram)
        svg = parsed.renderer.new.render(scene).to_xml
        doc = Nokogiri::XML(svg).remove_namespaces!
        doc.xpath("//g[@id='message-1']/polygon | //g[@id='message-1']/line")
      end

      it "matches the pinned primitive coordinates relative to the tip" do
        expect(actual_points).to eq(expected_points)
      end

      it "renders the pinned primitive types without a closed open head" do
        expect(rendered_heads.map(&:name)).to eq(reference_heads.map(&:name))
      end
    end
  end
end
