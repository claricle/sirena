# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Base do
  let(:reading_layout_class) do
    Class.new(described_class) do
      def scene(_diagram)
        Sirena::Layout::Scene.new(width: today.year, height: 0)
      end

      def read_today = today
      def read_theme = theme
    end
  end
  let(:layout) { reading_layout_class.new }

  describe "reader visibility" do
    it "lets a subclass read today" do
      layout.today = Date.new(1999, 1, 1)

      expect(layout.read_today).to eq(Date.new(1999, 1, 1))
    end

    it "lets a subclass read theme" do
      expect(layout.read_theme).to be_a(Sirena::Theme)
    end

    it "refuses an outside caller on today" do
      expect { layout.today }.to raise_error(NoMethodError, /private method/)
    end

    it "refuses an outside caller on theme" do
      expect { layout.theme }.to raise_error(NoMethodError, /private method/)
    end

    it "keeps the writers public" do
      expect(layout).to respond_to(:today=, :theme=)
    end
  end

  describe "#today" do
    it "is the memoised clock read, nothing more" do
      body = described_class.instance_method(:today).source_location
      line = File.readlines(body[0])[body[1]].strip

      expect(line).to eq("@today ||= Date.today")
    end

    it "falls back to the clock's date" do
      allow(Date).to receive(:today).and_return(Date.new(2001, 2, 3))

      expect(layout.read_today).to eq(Date.new(2001, 2, 3))
    end

    it "reads the clock once and memoises it" do
      allow(Date).to receive(:today).and_return(Date.new(2001, 2, 3))
      2.times { layout.read_today }

      expect(Date).to have_received(:today).once
    end
  end

  describe "a gantt render's use of today" do
    let(:source) do
      "gantt\n  dateFormat MM/DD\n  axisFormat %Y-%m-%d\n  " \
        "section Section\n  Task one : t1, 08/17, 3d\n"
    end
    let(:real_today) { Date.new(2026, 10, 11) }
    let(:past) { Date.new(2020, 1, 1) }

    before { allow(Date).to receive(:today).and_return(real_today) }

    it "gives the same output for today: nil as for today: Date.today" do
      expect(Sirena.render(source, today: nil))
        .to eq(Sirena.render(source, today: real_today))
    end

    # The first example alone passes for a layout that ignores today.
    it "gives different output for a pinned past date" do
      expect(Sirena.render(source, today: past))
        .not_to eq(Sirena.render(source, today: real_today))
    end
  end
end
