# frozen_string_literal: true

require "spec_helper"
require "digest"
require "rexml/document"
require "rexml/xpath"

RSpec.describe Sirena::Layout::Architecture do
  let(:source) do
    <<~MERMAID
      architecture-beta
        service frontend(browser)[Frontend]
        service backend(server)[Backend API]
        service db(database)[Database]

        frontend:R --> L:backend
        backend:R --> L:db
    MERMAID
  end

  it "keeps the default renderer byte-identical" do
    expect(Digest::SHA256.hexdigest(Sirena.render(source)))
      .to eq("33510274b9040b2f3d07dda7244f8c25f4e64b037b5ba0e01f03c49c903209fa")
  end

  it "places flat services and routes their relationships through elkrb" do
    allow(Sirena::Layout::ElkPlacement).to receive(:apply).and_call_original

    svg = Sirena.render(source, layout_engine: :elk)

    expect(Sirena::Layout::ElkPlacement).to have_received(:apply).once
    expect(svg).to include('id="service-frontend"', 'id="service-backend"',
                           'id="service-db"', 'id="edge-frontend-backend"')
  end

  it "places junctions through the same real graph" do
    with_junction = <<~MERMAID
      architecture-beta
        service api(server)[API]
        junction queue
        service worker(server)[Worker]

        api:R --> L:queue
        queue:R --> L:worker
    MERMAID

    expect(Sirena.render(with_junction, layout_engine: :elk))
      .to include('id="junction-queue"')
  end

  it "places nested groups through elkrb without losing edges or containment" do
    grouped = <<~MERMAID
      architecture-beta
        group outer(cloud)[Outer]
        group inner(cloud)[Inner] in outer
        service api(server)[API] in inner
        service worker(server)[Worker]

        api:R --> L:worker
    MERMAID

    allow(Sirena::Layout::ElkPlacement).to receive(:apply).and_call_original

    document = REXML::Document.new(Sirena.render(grouped, layout_engine: :elk))
    outer = REXML::XPath.first(document, "//*[@id='group-outer']/rect")
    inner = REXML::XPath.first(document, "//*[@id='group-inner']/rect")
    service = REXML::XPath.first(document, "//*[@id='service-api']/rect")
    geometry = lambda do |rect|
      %w[x y width height].to_h do |attribute|
        [attribute, Float(rect.attributes.fetch(attribute).to_s)]
      end
    end
    outer_box = geometry.call(outer)
    inner_box = geometry.call(inner)
    service_box = geometry.call(service)
    contains = lambda do |container, child|
      container["x"] <= child["x"] && container["y"] <= child["y"] &&
        container["x"] + container["width"] >=
          child["x"] + child["width"] &&
        container["y"] + container["height"] >=
          child["y"] + child["height"]
    end
    edge = REXML::XPath.first(document, "//*[@id='edge-api-worker']")

    expect([contains.call(inner_box, service_box),
            contains.call(outer_box, inner_box), edge.nil?])
      .to eq([true, true, false])
    expect(Sirena::Layout::ElkPlacement).to have_received(:apply).once
  end

  it "keeps an isolated empty group measurable" do
    empty_group = <<~MERMAID
      architecture-beta
        group platform(cloud)[Platform]
    MERMAID

    document = REXML::Document.new(
      Sirena.render(empty_group, layout_engine: :elk),
    )
    group = REXML::XPath.first(document, "//*[@id='group-platform']/rect")

    expect([group.attributes["width"], group.attributes["height"]]
      .map(&:to_s)).to eq(%w[112.0 112.0])
  end

  it "does not fall back when elkrb raises" do
    allow(Elkrb).to receive(:layout).and_raise(Elkrb::Error, "seeded")

    expect { Sirena.render(source, layout_engine: :elk) }
      .to raise_error(Sirena::Layout::LayoutError, /seeded/)
  end
end
