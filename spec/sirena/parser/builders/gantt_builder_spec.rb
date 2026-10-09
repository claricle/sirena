# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Gantt do
  subject(:diagram) { described_class.new.apply(tree) }

  def task_entry(description, *fields)
    parts = fields.map { |f| { field: f } }
    { task_entry: { description: description,
                    task_details: { parts: parts } } }
  end

  context "with an array tree and noise" do
    let(:tree) { ["noise", { header: "gantt" }, { title: "T" }] }

    it "skips non-hash entries" do
      expect(diagram.title).to eq("T")
    end
  end

  context "with a task before any section" do
    let(:tree) do
      [task_entry("lonely"), { task_entry: { description: "bare" } }]
    end

    it "opens a Default section and tolerates missing details",
       :aggregate_failures do
      expect(diagram.sections.map(&:name)).to eq(["Default"])
      descriptions = diagram.sections.first.tasks.map(&:description)
      expect(descriptions).to eq(%w[lonely bare])
    end
  end

  context "with task details of different shapes" do
    let(:tree) do
      [
        { section: "S" },
        task_entry("three", "id1", "2024-01-01", "2d"),
        task_entry("after", "after other", "3d"),
        task_entry("after-end", "after other", "2024-02-01"),
        task_entry("until", "until other"),
        task_entry("two", "2024-01-01", "2024-01-05"),
        { task_entry: { description: "single",
                        task_details: { parts: { field: "2024-03-03" } } } },
        { task_entry: { description: "weird", task_details: "text" } },
      ]
    end

    let(:tasks) { diagram.sections.first.tasks.to_h { |t| [t.description, t] } }
    let(:after) { tasks["after"] }
    let(:after_end) { tasks["after-end"] }

    it "takes the first of three positional fields as the id" do
      expect([tasks["three"].id, tasks["three"].start_date,
              tasks["three"].duration]).to eq(["id1", "2024-01-01", "2d"])
    end

    it "records dependencies and treats a lone date after one as the end",
       :aggregate_failures do
      expect([after.after_task, after.duration]).to eq(["other", "3d"])
      expect([after_end.after_task, after_end.end_date, after_end.start_date])
        .to eq(["other", "2024-02-01", nil])
      expect(tasks["until"].until_task).to eq("other")
    end

    it "uses position for start and end without an id" do
      expect([tasks["two"].id, tasks["two"].start_date,
              tasks["two"].end_date]).to eq([nil, "2024-01-01", "2024-01-05"])
    end

    it "accepts a single parts hash and ignores non-hash details",
       :aggregate_failures do
      expect(tasks["single"].start_date).to eq("2024-03-03")
      expect(tasks["weird"].start_date).to be_nil
    end
  end

  context "with click handlers" do
    let(:tree) do
      [
        { section: "S" },
        task_entry("a", "ida", "2024-01-01", "1d"),
        task_entry("b", "idb", "2024-01-01", "1d"),
        task_entry("c", "idc", "2024-01-01", "1d"),
        task_entry("d", "2024-01-01", "1d"),
        { click_id: "ida", href: "http://example.com" },
        { click_id: "idb", callback: "doIt" },
        { click_id: "idc" },
        { click_id: "missing", href: "x" },
      ]
    end

    it "attaches href and callback to the matching tasks only",
       :aggregate_failures do
      tasks = diagram.sections.first.tasks.to_h { |t| [t.description, t] }
      expect(tasks["a"].click_href).to eq("http://example.com")
      expect(tasks["b"].click_callback).to eq("doIt")
      expect([tasks["c"].click_href, tasks["c"].click_callback]).to all(be_nil)
      expect([tasks["d"].click_href, tasks["d"].click_callback]).to all(be_nil)
    end
  end
end
