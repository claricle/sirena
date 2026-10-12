# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  def centers_for(case_id)
    path = File.expand_path("../../mermaid/class_diagram/#{case_id}", __dir__)
    diagram = Sirena::Parser::ClassDiagram.new.parse(File.read(path))
    described_class.new.call(diagram).children.map do |node|
      node.x + (node.width / 2.0)
    end
  end

  {
    "classdiagram_spec-4440fcd7.mmd" => 2,
    "yari-8803143a.mmd" => 2,
  }.each do |case_id, count|
    it "places every class of #{case_id}" do
      expect(centers_for(case_id).size).to eq(count)
    end

    it "centers the vertical namespace siblings in #{case_id}" do
      centers = centers_for(case_id).map { |center| center.round(3) }
      expect(centers.uniq.size).to eq(1)
    end
  end
end
