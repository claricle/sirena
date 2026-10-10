# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::UserJourney do
  # mmdc keeps a task written before the first `section` and draws no
  # header for it.
  describe "a task before the first section" do
    let(:source) do
      "journey\n  Lead: 3: Me\n  section S1\n  Next: 4: You\n"
    end
    let(:svg) { Sirena::Engine.new.render(source) }

    it "renders the task name" do
      expect(svg).to include(">Lead<")
    end

    it "renders the task score and actor" do
      expect(svg).to include(">3<").and include(">Me<")
    end

    it "draws a header only for the named section" do
      expect(svg.scan('class="journey-section"').size).to eq(1)
    end
  end
end
