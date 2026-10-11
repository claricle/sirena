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
  let(:grouped_source) do
    <<~MERMAID
      architecture-beta
        group outer(cloud)[Outer]
        group inner(cloud)[Inner] in outer
        service api(server)[API] in inner
        service worker(server)[Worker]

        api:R --> L:worker
    MERMAID
  end
  let(:junction_source) do
    <<~MERMAID
      architecture-beta
        service api(server)[API]
        junction queue
        service worker(server)[Worker]

        api:R --> L:queue
        queue:R --> L:worker
    MERMAID
  end
  let(:elk_calls) { [] }
  let(:nested_evidence) do
    document = REXML::Document.new(
      Sirena.render(grouped_source, layout_engine: :elk),
    )
    attributes = %w[x y width height]
    boxes = %w[group-outer group-inner service-api].map do |id|
      rect = REXML::XPath.first(document, "//*[@id='#{id}']/rect")
      attributes.to_h do |attribute|
        [attribute, Float(rect.attributes.fetch(attribute).to_s)]
      end
    end
    outer, inner, service = boxes
    inner_contains = inner["x"] <= service["x"] &&
      inner["y"] <= service["y"] &&
      inner["x"] + inner["width"] >= service["x"] + service["width"] &&
      inner["y"] + inner["height"] >= service["y"] + service["height"]
    outer_contains = outer["x"] <= inner["x"] &&
      outer["y"] <= inner["y"] &&
      outer["x"] + outer["width"] >= inner["x"] + inner["width"] &&
      outer["y"] + outer["height"] >= inner["y"] + inner["height"]
    edge = REXML::XPath.first(document, "//*[@id='edge-api-worker']")
    [inner_contains, outer_contains, edge.nil?, elk_calls.length]
  end

  before do
    allow(Sirena::Layout::ElkPlacement).to receive(:apply)
      .and_wrap_original do |method, *args|
        elk_calls << args
        method.call(*args)
      end
  end

  it "keeps the default renderer byte-identical" do
    expect(Digest::SHA256.hexdigest(Sirena.render(source)))
      .to eq("33510274b9040b2f3d07dda7244f8c25f4e64b037b5ba0e01f03c49c903209fa")
  end

  it "places flat services and routes their relationships through elkrb" do
    svg = Sirena.render(source, layout_engine: :elk)
    ids = %w[service-frontend service-backend service-db
             edge-frontend-backend]

    expect([elk_calls.length, ids.all? { |id| svg.include?(%(id="#{id}")) }])
      .to eq([1, true])
  end

  it "places junctions through the same real graph" do
    expect(Sirena.render(junction_source, layout_engine: :elk))
      .to include('id="junction-queue"')
  end

  it "places nested groups through elkrb without losing edges or containment" do
    expect(nested_evidence).to eq([true, true, false, 1])
  end

  it "keeps an isolated empty group measurable" do
    input = grouped_source.lines.first(2).join
    document = REXML::Document.new(Sirena.render(input, layout_engine: :elk))
    group = REXML::XPath.first(document, "//*[@id='group-outer']/rect")
    dimensions = %w[width height].map { |key| group.attributes[key].to_s }
    expect(dimensions).to eq(%w[112.0 112.0])
  end

  it "does not fall back when elkrb raises" do
    allow(Elkrb).to receive(:layout).and_raise(Elkrb::Error, "seeded")

    expect { Sirena.render(source, layout_engine: :elk) }
      .to raise_error(Sirena::Layout::LayoutError, /seeded/)
  end
end
