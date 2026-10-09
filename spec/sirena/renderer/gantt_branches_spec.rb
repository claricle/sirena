# frozen_string_literal: true

require "spec_helper"
require "date"

RSpec.describe Sirena::Renderer::Gantt do
  subject(:renderer) { described_class.new }

  def xml_for(graph)
    renderer.render(graph).to_xml
  end

  let(:timeline) { { total_days: 10, start_date: Date.new(2024, 1, 1) } }

  def task(description, **attrs)
    { description: description, **attrs }
  end

  it "draws no timeline axis when the graph has no timeline",
     :aggregate_failures do
    xml = xml_for({ title: "T", sections: [{ name: "S", tasks: [task("d")] }] })
    expect(xml.scan("<text").size).to eq(3)
    expect(xml).to include(">T<").and include(">S<").and include(">d<")
  end

  it "draws no date labels for a zero-day timeline" do
    xml = xml_for({ timeline: { total_days: 0 }, sections: [] })
    expect(xml).not_to include("<text")
  end

  it "labels a 10-day timeline every 7 days in month-day form" do
    xml = xml_for({ timeline: timeline, sections: [] })
    expect(xml.scan(/>(\d\d-\d\d)</).flatten).to eq(%w[01-01 01-08])
  end

  it "applies the graph's axis format to date labels" do
    xml = xml_for({ timeline: timeline, axis_format: "%d/%m", sections: [] })
    expect(xml.scan(%r{>(\d\d/\d\d)<}).flatten).to eq(%w[01/01 08/01])
  end

  describe "bar colours" do
    let(:colours) { %w[#D9534F #5CB85C #5BC0DE #428BCA] }
    let(:tasks) do
      [task("c", critical: true, start_x: 10, width: 50),
       task("d", done: true, start_x: 10, width: 50),
       task("a", active: true, start_x: 10, width: 50),
       task("p", start_x: 10, width: 50),
       task("n", start_x: nil, width: 5)]
    end
    let(:xml) do
      xml_for({ timeline: timeline, sections: [{ name: "S", tasks: tasks }] })
    end
    let(:counts) { colours.map { |c| xml.scan(%(fill="#{c}")).size } }

    it "colours bars by status and draws none for a task without a position" do
      expect(counts).to eq([1, 1, 1, 1])
    end
  end
end
