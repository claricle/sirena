# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/gantt"

RSpec.describe Sirena::Parser::Gantt do
  subject(:tasks) { described_class.new.parse(source).sections.first.tasks }

  let(:source) do
    <<~GANTT
      gantt
        section Tasks
        One :a, 2024-01-01, 1d
        Two :b, 2024-01-02, 1d
        click a href https://example.test/a
        click b call handleB
    GANTT
  end
  let(:actual) do
    tasks.map do |task|
      [task.id, task.click_href, task.click_callback]
    end
  end

  it "attaches href and callback declarations to their tasks" do
    expect(actual).to eq([
                           ["a", "https://example.test/a", nil],
                           ["b", nil, "handleB"],
                         ])
  end
end
