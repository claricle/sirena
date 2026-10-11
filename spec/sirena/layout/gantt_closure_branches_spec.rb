# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  let(:helper) { GanttCoverageScene }
  let(:first_task) { "section A\nT1 :a, 2024-01-01, 2d\n" }

  it "leaves a dated task open-ended when its until task is unknown" do
    body = "#{first_task}T2 :2024-01-05, until zz\n"

    expect(helper.spans(helper.scene(body))[1])
      .to eq([Date.new(2024, 1, 5), nil])
  end

  it "leaves a dated task open-ended when its until task has no start yet" do
    body = "#{first_task}T2 :2024-01-05, until c\nT3 :c, after zz\n"

    expect(helper.spans(helper.scene(body))[1])
      .to eq([Date.new(2024, 1, 5), nil])
  end
end
