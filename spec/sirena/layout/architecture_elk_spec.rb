# frozen_string_literal: true

require "spec_helper"
require "digest"

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

  it "fails loudly instead of silently flattening group containment" do
    grouped = <<~MERMAID
      architecture-beta
        group platform(cloud)[Platform]
        service api(server)[API] in platform
    MERMAID

    expect { Sirena.render(grouped, layout_engine: :elk) }
      .to raise_error(Sirena::Layout::LayoutError, /group containment/)
  end

  it "does not fall back when elkrb raises" do
    allow(Elkrb).to receive(:layout).and_raise(Elkrb::Error, "seeded")

    expect { Sirena.render(source, layout_engine: :elk) }
      .to raise_error(Sirena::Layout::LayoutError, /seeded/)
  end
end
