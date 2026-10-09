# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/architecture_edge_router"

RSpec.describe Sirena::Renderer::ArchitectureEdgeRouter do
  let(:router) { described_class.new }

  def endpoint(point, box, side)
    { point: point, box: box, side: side }
  end

  it "leaves a two-point searched path unchanged" do
    from = endpoint({ x: 10, y: 10 }, { x: 0, y: 0, width: 10, height: 20 }, "R")
    to = endpoint({ x: 90, y: 10 }, { x: 90, y: 0, width: 10, height: 20 }, "L")
    points = [from[:point], to[:point]]
    allow(router).to receive_messages(
      straight_clear?: false,
      shortest_path: points,
    )

    expect(router.route(from: from, to: to, obstacles: [])).to equal(points)
  end

  it "retries the search with margin coordinates" do
    from = endpoint({ x: 10, y: 10 }, { x: 0, y: 0, width: 10, height: 20 }, "R")
    to = endpoint({ x: 90, y: 10 }, { x: 90, y: 0, width: 10, height: 20 }, "L")
    margins = []
    allow(router).to receive(:straight_clear?).and_return(false)
    allow(router).to receive(:build_grid).and_wrap_original do |method, *args, **keywords|
      margins << keywords.fetch(:margin)
      method.call(*args, **keywords)
    end
    allow(router).to receive(:search_grid).and_return(nil, [from[:point], to[:point]])

    router.route(from: from, to: to, obstacles: [])

    expect(margins).to eq([false, true])
  end

  it "falls back to the direct segment after both searches fail" do
    from = endpoint({ x: 10, y: 10 }, { x: 0, y: 0, width: 10, height: 20 }, "R")
    to = endpoint({ x: 90, y: 10 }, { x: 90, y: 0, width: 10, height: 20 }, "L")
    allow(router).to receive_messages(straight_clear?: false, search_grid: nil)

    expect(router.route(from: from, to: to, obstacles: []))
      .to eq([from[:point], to[:point]])
  end

  border_cases = [
    {
      name: "vertical",
      from: { point: { x: 20, y: 20 }, box: { x: 0, y: 0, width: 20, height: 20 }, side: "B" },
      to: { point: { x: 20, y: 100 }, box: { x: 0, y: 100, width: 20, height: 20 }, side: "T" },
      obstacle: { x: 20, y: 40, width: 30, height: 40 },
    },
    {
      name: "horizontal",
      from: { point: { x: 20, y: 20 }, box: { x: 0, y: 0, width: 20, height: 20 }, side: "R" },
      to: { point: { x: 100, y: 20 }, box: { x: 100, y: 0, width: 20, height: 20 }, side: "L" },
      obstacle: { x: 40, y: 20, width: 40, height: 30 },
    },
  ]

  border_cases.each do |test_case|
    it "treats a #{test_case[:name]} segment on an obstacle border as clear" do
      expect(router.route(
               from: test_case[:from],
               to: test_case[:to],
               obstacles: [test_case[:obstacle]],
             )).to eq([test_case[:from][:point], test_case[:to][:point]])
    end
  end

  it "routes a vertical segment around an obstacle containing its fixed axis" do
    from = endpoint({ x: 20, y: 20 }, { x: 0, y: 0, width: 40, height: 20 }, "B")
    to = endpoint({ x: 20, y: 120 }, { x: 0, y: 120, width: 40, height: 20 }, "T")
    obstacle = { x: 10, y: 40, width: 20, height: 40 }

    expect(router.route(from: from, to: to, obstacles: [obstacle]).length).to be > 2
  end
end
