# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Base, "#render" do
  let(:fractional) { /font-size="\d+\.5"/ }

  {
    Sirena::Renderer::Info => "info",
    Sirena::Renderer::Pie => "pie\n \"a\" : 1\n \"b\" : 2",
    Sirena::Renderer::Packet => "packet-beta\n 0-7: \"x\"",
    Sirena::Renderer::Radar => "radar-beta\n axis a,b,c\n curve c1{1,2,3}",
    Sirena::Renderer::Timeline => "timeline\n 2020 : x",
    Sirena::Renderer::Treemap => "treemap-beta\n \"A\"\n  \"B\": 5",
    Sirena::Renderer::UserJourney => "journey\n title T\n section S\n T: 5: Me",
    Sirena::Renderer::Kanban => "kanban\n col\n  t1[task]",
    Sirena::Renderer::StateDiagram =>
      "stateDiagram-v2\n [*] --> A\n A --> B: go\n B --> [*]",
    Sirena::Renderer::Quadrant =>
      "quadrantChart\n x-axis L --> R\n y-axis B --> T\n P: [0.3, 0.6]",
  }.each do |renderer, source|
    it "keeps a fractional font size in #{renderer.name}" do
      allow(renderer).to receive(:new).and_wrap_original do |original, **opts|
        original.call(**opts).tap do |instance|
          instance.singleton_class.prepend(FractionalFontScene::Widening)
        end
      end

      expect(Sirena::Engine.new.render(source)).to match(fractional)
    end
  end

  it "keeps a fractional font size in Sirena::Renderer::Error" do
    scene = FractionalFontScene.widen(Sirena::Layout::Error.from_graph({}))

    expect(Sirena::Renderer::Error.new.render(scene).to_xml).to match(fractional)
  end
end
