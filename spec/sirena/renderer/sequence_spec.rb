# frozen_string_literal: true

require "spec_helper"
require "digest"

# Single-user (this file only), pure — no let/expect/described_class.
module SequenceSpecHelpers
  module_function

  # These assertions exist because the corpus sweep cannot make them. It
  # checks that a well-formed SVG comes out, so an arrow drawn with the
  # wrong line style or a head mermaid does not draw still scores a pass.
  #
  # Every expectation below is taken from mmdc 11.12.0's own output for the
  # same source: messageLine0/messageLine1 for the line style, and the
  # presence of marker-end / marker-start for the heads.
  def message_group(arrow, source = nil)
    xml = Sirena.render(source || "sequenceDiagram\n    A#{arrow}B: m\n")
    xml[%r{<g id="message-0".*?</g>}m]
  end

  def arrowheads(arrow)
    message_group(arrow).scan("<polygon").size
  end

  def dashed?(arrow)
    message_group(arrow).include?("stroke-dasharray")
  end

  def rtl_group(arrow)
    source = "sequenceDiagram\n    participant A\n    participant B\n    " \
             "B#{arrow}A: m\n"
    message_group(arrow, source)
  end

  # A straight shaft has no horizontal run here, so it collapsed to
  # nothing: A->A drew neither a line nor a head. mermaid loops back to
  # the same lifeline.
  def self_group(arrow)
    xml = Sirena.render(
      "sequenceDiagram\n    participant A\n    A#{arrow}A: self\n",
    )
    xml[%r{<g id="message-0".*?</g>}m]
  end

  def message_line(arrow, axis, source = nil)
    line = message_group(arrow, source)[/<line[^>]*>/]
    line[/#{axis}="([\d.]+)"/, 1].to_f
  end
end

RSpec.describe Sirena::Renderer::Sequence do
  describe "head style" do
    # Counting polygons alone let a cross — which is drawn with lines —
    # be added to a "headless" arrow without failing anything.
    %w[-> -->].each do |arrow|
      it "draws nothing but the shaft on #{arrow}" do
        group = SequenceSpecHelpers.message_group(arrow)

        expect(group.scan("<polygon").size).to eq(0)
        expect(group.scan("<line").size).to eq(1)
        expect(group[/<line[^>]*>/]).to include('x2="220.0"')
      end
    end

    it "draws one arrowhead, at the target, on ->>" do
      group = SequenceSpecHelpers.message_group("->>")

      expect(group.scan("<polygon").size).to eq(1)
      expect(group[/<polygon[^>]*points="([^"]*)"/, 1])
        .to eq("220,120 212,116 212,124")
    end

    it "draws an arrowhead at both ends of <<->>, one per end" do
      # A count alone would pass with two heads stacked at the same end.
      tips = SequenceSpecHelpers.message_group("<<->>").scan(/<polygon[^>]*points="(\d+),/).flatten

      expect(tips).to contain_exactly("80", "220")
    end

    it "draws a stroked cross on -x, not a filled head" do
      group = SequenceSpecHelpers.message_group("-x")

      # Two strokes that cross, and no polygon: mermaid's crosshead is
      # stroke-only (fill="none"), unlike every other head it draws.
      expect(group.scan("<polygon").size).to eq(0)
      expect(group.scan("<line").size).to eq(3)

      # The two strokes straddle the tip rather than stopping at it, and
      # the shaft runs its full length because a cross takes no inset.
      shaft, *strokes = group.scan(/<line[^>]*>/)
      expect(shaft).to include('x1="80.0"').and include('x2="220.0"')
      expect(strokes.map { |l| l[/x1="[\d.]+" y1="[\d.]+" x2="[\d.]+" y2="[\d.]+"/] })
        .to contain_exactly('x1="216.0" y1="116.0" x2="224.0" y2="124.0"',
                            'x1="216.0" y1="124.0" x2="224.0" y2="116.0"')
      # Stroke-only is the point: mermaid's crosshead sets fill="none".
      expect(strokes).to all(include('stroke="#000000"'))
      expect(strokes).to all(include('stroke-width="2"'))
    end

    it "draws a filled concave chevron on -)" do
      # mermaid's filled-head marker, path "M 18,7 L9,13 L14,7 L9,1 Z" — a
      # filled four-point head with a notch, not two open strokes. The fill
      # is the point: an unfilled polygon of the same shape looks wrong.
      polygon = SequenceSpecHelpers.message_group("-)")[/<polygon[^>]*>/]

      expect(polygon).to include('fill="#000000"')
      expect(polygon[/points="([^"]*)"/, 1]).to eq("220,120 212,116 215.2,120 212,124")
    end

    it "draws one barb below the line on -|/" do
      # mermaid's solidBottomArrowHead: a single barb, not a full head.
      polygon = SequenceSpecHelpers.message_group("-|/")[/<polygon[^>]*>/]

      expect(polygon).to include('fill="#000000"')
      expect(polygon[/points="([^"]*)"/, 1]).to eq("220,120 212,124 212,120")
    end

    it "draws one barb above the line on -|\\" do
      polygon = SequenceSpecHelpers.message_group("-|\\")[/<polygon[^>]*>/]

      expect(polygon[/points="([^"]*)"/, 1]).to eq("220,120 212,116 212,120")
    end

    # mermaid's stickBottomArrowHead is `M 0 7 L 7 0` with fill="none" —
    # one stroke, where the solid variant is a filled wedge. Drawing both
    # as polygons made `-//` and `-|/` the same picture.
    {
      "-//" => 'x1="220.0" y1="120.0" x2="212.0" y2="124.0"',
      "-\\\\" => 'x1="220.0" y1="120.0" x2="212.0" y2="116.0"',
    }.each do |arrow, stroke|
      it "draws one unfilled stroke on #{arrow}" do
        group = SequenceSpecHelpers.message_group(arrow)

        expect(group.scan("<polygon").size).to eq(0)
        expect(group.scan(/<line[^>]*>/).last).to include(stroke)
      end
    end

    # The reversed spellings put the head on the source end. mermaid marks
    # every head `orient="auto-start-reverse"`, so the same marker at the
    # start is rotated 180 degrees — a "bottom" head sits above the line.
    it "draws the barb of /|- at the source, flipped" do
      group = SequenceSpecHelpers.message_group("/|-")

      expect(group[/<polygon[^>]*points="([^"]*)"/, 1])
        .to eq("80,120 88,116 88,120")
    end

    it "draws the stroke of //- at the source, flipped" do
      group = SequenceSpecHelpers.message_group("//-")

      expect(group.scan("<polygon").size).to eq(0)
      expect(group.scan(/<line[^>]*>/).last)
        .to include('x1="80.0" y1="120.0" x2="88.0" y2="116.0"')
    end

    it "insets the shaft at the end that carries a filled head" do
      # A wedge occupies the last few pixels of the shaft, so the shaft
      # stops short of it — at whichever end it is. Insetting the target
      # end regardless drew /|- through its own barb.
      expect(SequenceSpecHelpers.message_group("/|-")[/<line[^>]*>/])
        .to include('x1="88.0"').and include('x2="220.0"')
    end

    it "runs the shaft up to the tip under a concave head" do
      # The chevron of `-)` meets the centreline at its notch, not at its
      # back edge, so insetting the shaft left a gap between 212 and 215.2.
      headless = SequenceSpecHelpers.message_group("->")[/<line[^>]*>/]

      expect(SequenceSpecHelpers.message_group("-)")[/<line[^>]*>/]).to eq(headless)
    end

    it "runs the shaft full length under a stick head" do
      # A stick is one diagonal stroke from the tip, so it covers none of
      # the shaft. Insetting for it left an eight-pixel gap where mermaid
      # attaches the marker and draws none.
      headless = SequenceSpecHelpers.message_group("->")[/<line[^>]*>/]

      expect(SequenceSpecHelpers.message_group("//-")[/<line[^>]*>/])
        .to include('x1="80.0"').and include('x2="220.0"')
      expect(SequenceSpecHelpers.message_group("-//")[/<line[^>]*>/]).to eq(headless)
    end

    # Which way a head is rotated follows the direction from the shaft to
    # the tip, not which end of the line the head sits on. Keying on the
    # end drew every right-to-left message as the mirror of mmdc's.
    describe "a right-to-left message" do
      it "flips the target barb of -|/ to the other side" do
        expect(SequenceSpecHelpers.rtl_group("-|/")[/<polygon[^>]*points="([^"]*)"/, 1])
          .to eq("80,120 88,116 88,120")
      end

      it "draws the source barb of /|- below, as left-to-right draws it" do
        expect(SequenceSpecHelpers.rtl_group("/|-")[/<polygon[^>]*points="([^"]*)"/, 1])
          .to eq("220,120 212,124 212,120")
      end
    end

    it "mirrors the chevron on a right-to-left message" do
      rtl = <<~MERMAID
        sequenceDiagram
            participant A
            participant B
            B-)A: m
      MERMAID
      polygon = SequenceSpecHelpers.message_group("-)", rtl)[/<polygon[^>]*>/]

      expect(polygon[/points="([^"]*)"/, 1]).to eq("80,120 88,116 84.8,120 88,124")
    end
  end

  describe "line style" do
    it "draws -> solid" do
      expect(SequenceSpecHelpers.dashed?("->")).to be(false)
    end

    it "draws --> dashed" do
      expect(SequenceSpecHelpers.dashed?("-->")).to be(true)
    end

    it "draws ->> solid" do
      expect(SequenceSpecHelpers.dashed?("->>")).to be(false)
    end

    it "draws -->> dashed" do
      expect(SequenceSpecHelpers.dashed?("-->>")).to be(true)
    end

    it "draws <<-->> dashed with one head at each end" do
      tips = SequenceSpecHelpers.message_group("<<-->>").scan(/<polygon[^>]*points="(\d+),/).flatten

      expect(SequenceSpecHelpers.dashed?("<<-->>")).to be(true)
      expect(tips).to contain_exactly("80", "220")
    end
  end

  describe "a participant messaging itself" do
    it "draws a loop for a headless self-message" do
      group = SequenceSpecHelpers.self_group("->")

      # Reaching right, not left: the loop must not cross the lifeline into
      # the previous participant's column.
      expect(group[/<path[^>]*d="([^"]*)"/, 1])
        .to eq("M 80,110 C 136,110 136,130 80,130")
      expect(group.scan("<polygon").size).to eq(0)
    end

    it "draws a loop and one head at its return for ->>" do
      group = SequenceSpecHelpers.self_group("->>")

      expect(group.scan("<polygon").size).to eq(1)
      expect(group[/<polygon[^>]*points="([^"]*)"/, 1])
        .to eq("80,130 88,126 88,134")
    end

    it "draws a head at each end of a bidirectional self-message" do
      # mmdc emits both a marker-start and a marker-end here.
      group = SequenceSpecHelpers.self_group("<<->>")
      tips = group.scan(/<polygon[^>]*points="[\d.]+,([\d.]+)/).flatten

      expect(tips).to contain_exactly("110", "130")
    end

    it "lifts the label clear of the loop" do
      # The loop reaches half its height above the message line, so the
      # ordinary offset put the text baseline on the loop's top edge.
      group = SequenceSpecHelpers.self_group("->>")
      label_y = group[/<text[^>]*y="([\d.]+)"/, 1].to_f
      loop_top = group[/<path[^>]*d="M [\d.]+,([\d.]+)/, 1].to_f

      expect(label_y).to be < loop_top
    end

    it "dashes the loop for a dotted self-message" do
      expect(SequenceSpecHelpers.self_group("-->")).to include("stroke-dasharray")
    end
  end

  describe "line inset" do
    it "shortens the line at the source only when that end carries a head" do
      expect(SequenceSpecHelpers.message_line("<<->>", "x1")).to be > SequenceSpecHelpers.message_line("->>", "x1")
    end

    it "does not shorten the line when there is no head" do
      expect(SequenceSpecHelpers.message_line("->", "x2")).to be > SequenceSpecHelpers.message_line("->>", "x2")
    end

    it "insets towards the head on a right-to-left message" do
      # Unsigned, this ran the shaft past its own head: B<<->>A started at
      # 228 while the source head occupied 212 to 220.
      rtl = <<~MERMAID
        sequenceDiagram
            participant A
            participant B
            B<<->>A: m
      MERMAID

      expect(SequenceSpecHelpers.message_line("<<->>", "x1", rtl)).to eq(212.0)
      expect(SequenceSpecHelpers.message_line("<<->>", "x2", rtl)).to eq(88.0)
    end
  end

  describe "empty diagram" do
    # mmdc renders `sequenceDiagram` with no body as a near-empty canvas:
    # no actor boxes, no lifelines, nothing in <g/>. Sirena used to reject
    # this (diagram invalid without a participant); once zero participants
    # became valid, the renderer's width/height formulas — sized for at
    # least one lifeline pair — produced a 120x220 canvas with nothing
    # drawn in it, a diagram mmdc never renders at any size. Both must be
    # true: nothing drawn, AND a canvas that does not imply a phantom
    # participant pair.
    it "draws nothing and does not size the canvas as though a participant were present" do
      xml = Sirena.render("sequenceDiagram")

      expect(xml).not_to match(/<rect|<line|<polygon|<text/)
      expect(xml).to match(%r{<svg[^>]*>\s*</svg>}m)
      expect(xml).to include('viewBox="0 0 40 40"')
    end
  end

  describe "typed Scene conversion" do
    let(:source) do
      "sequenceDiagram\nparticipant A\nparticipant B\nA->>B: hello\n"
    end
    let(:decorated_digest) do
      "462eb6aca8e9ffd45bde342925333555a688d1242f677edcaf49f445f45ed9a8"
    end

    it "emits the font sizes resolved by the injected theme" do
      xml = Sirena.render(source, theme: "high_contrast")
      participant = xml[%r{<g id="participant-A".*?</g>}m]
      message = xml[%r{<g id="message-0".*?</g>}m]

      expect([participant, message])
        .to match([include('font-size="18"'), include('font-size="18"')])
    end

    it "preserves the pre-conversion bytes with a note and activation" do
      decorated = "sequenceDiagram\nparticipant A\nparticipant B\n" \
                  "Note over A: omitted\nactivate A\nA->>B: hello\n" \
                  "deactivate A\n"

      expect(Digest::SHA256.hexdigest(Sirena.render(decorated)))
        .to eq(decorated_digest)
    end

    describe "released protected hooks" do
      let(:expected_hook_arities) do
        {
          calculate_width: 1, calculate_height: 1,
          calculate_participant_positions: 1, render_participants: 3,
          render_participant: 3, render_participant_box: 4, render_actor: 4,
          render_lifelines: 3, render_messages: 3, render_message: 4,
          render_arrow: 6, render_filled_arrowhead: 5,
          render_open_arrowhead: 5, render_cross: 3,
          render_message_label: 5, render_notes: 3
        }
      end
      let(:actual_hook_arities) do
        expected_hook_arities.to_h do |name, _arity|
          method = described_class.instance_method(name)
          protected = described_class.protected_method_defined?(name)
          [name, [protected, method.arity]]
        end
      end

      it "preserves names and arities" do
        expected = expected_hook_arities.transform_values do |arity|
          [true, arity]
        end

        expect(actual_hook_arities).to eq(expected)
      end
    end

    describe "graph-based compatibility" do
      subject(:hook_evidence) do
        graph = Sirena::Layout::Sequence.new.build_graph(
          Sirena::Parser::Sequence.new.parse(source),
        )
        renderer = hook_renderer_class.new
        svg = renderer.render(graph)
        [renderer.calls, svg.width]
      end

      let(:hook_renderer_class) do
        Class.new(described_class) do
          attr_reader :calls

          def initialize(...)
            super
            @calls = []
          end

          protected

          def calculate_width(graph)
            @calls << :calculate_width
            super + 7
          end

          def calculate_height(graph)
            @calls << :calculate_height
            super
          end

          def calculate_participant_positions(participants)
            @calls << :calculate_participant_positions
            super
          end

          def render_lifelines(positions, message_count, svg)
            @calls << :render_lifelines
            super
          end

          def render_messages(graph, positions, svg)
            @calls << :render_messages
            super
          end

          def render_participants(participants, positions, svg)
            @calls << :render_participants
            super
          end

          def render_notes(notes, positions, svg)
            @calls << :render_notes
            super
          end
        end
      end
      let(:expected_hook_evidence) do
        [
          %i[
            calculate_width calculate_height calculate_participant_positions
            render_lifelines render_messages render_participants render_notes
          ],
          407.0,
        ]
      end

      it "keeps public Hash rendering on the released hook chain" do
        expect(hook_evidence).to eq(expected_hook_evidence)
      end
    end

    describe "typed final geometry" do
      subject(:rendered_geometry) do
        scene = Sirena::Layout::Sequence.new.call(
          Sirena::Parser::Sequence.new.parse(source),
        )
        scene.width = 777
        scene.height = 333
        scene.view_box = "0 0 777 333"
        scene.participants.first.x = 888
        scene.participants.first.width = 321
        scene.participants.first.label.x = 889
        scene.lifelines.first.x1 = 999
        scene.lifelines.first.x2 = 999
        scene.messages.first.shaft.x1 = 666
        scene.messages.first.label.x = 667

        svg = typed_guard_renderer_class.new.render(scene)
        lifeline = svg.children.grep(Sirena::Svg::Line).first
        message = svg.children.grep(Sirena::Svg::Group)
          .find { |group| group.id == "message-0" }
        participant = svg.children.grep(Sirena::Svg::Group)
          .find { |group| group.id == "participant-A" }
        shaft = message.children.grep(Sirena::Svg::Line).first
        message_label = message.children.grep(Sirena::Svg::Text).first
        box = participant.children.grep(Sirena::Svg::Rect).first
        participant_label = participant.children.grep(Sirena::Svg::Text).first
        [
          svg.width, svg.height, svg.view_box,
          box.x, box.width, participant_label.x,
          lifeline.x1, lifeline.x2,
          shaft.x1, message_label.x
        ]
      end

      let(:typed_guard_renderer_class) do
        Class.new(described_class) do
          protected

          def calculate_width(_graph)
            raise "typed rendering recovered width"
          end

          def calculate_height(_graph)
            raise "typed rendering recovered height"
          end

          def calculate_participant_positions(_participants)
            raise "typed rendering recovered participant positions"
          end

          def render_lifelines(_positions, _message_count, _svg)
            raise "typed rendering recovered lifelines"
          end

          def render_messages(_graph, _positions, _svg)
            raise "typed rendering recovered messages"
          end

          def render_participants(_participants, _positions, _svg)
            raise "typed rendering recovered participants"
          end
        end
      end
      let(:expected_rendered_geometry) do
        [777.0, 333.0, "0 0 777 333",
         888.0, 321.0, 889.0, 999.0, 999.0, 666.0, 667.0]
      end

      it "serializes stored canvas, participant, lifeline, " \
         "and message values" do
        expect(rendered_geometry).to eq(expected_rendered_geometry)
      end
    end

    it "keeps the released actor hook independent of participant data" do
      group = Sirena::Svg::Group.new

      described_class.new.send(:render_actor, 20, 20, nil, group)

      expect(group.to_xml.scan(/<(circle|line)\b/).flatten.tally)
        .to eq("circle" => 1, "line" => 4)
    end
  end
end
