# frozen_string_literal: true

require "spec_helper"
require "nokogiri"

RSpec.describe Sirena::Layout::GitGraph do
  let(:duplicate_case) do
    "should_log_a_warning_when_two_commits_have_the_s-8c8c51d0"
  end
  let(:duplicate_source) do
    File.read("spec/mermaid/gitgraph/#{duplicate_case}.mmd")
  end
  let(:duplicate_scene) do
    described_class.new.call(Sirena::Parser::GitGraph.new.parse(duplicate_source))
  end

  def label_count(svg, label)
    Nokogiri::XML(svg).xpath("//*[local-name()='text']").count do |node|
      node.text == label
    end
  end

  def reference_commit_count
    path = "spec/fixtures_mermaid/gitgraph/#{duplicate_case}.svg"
    document = Nokogiri::XML(File.read(path))
    selector = "//*[contains(concat(' ', @class, ' '), ' commit ')]"
    nodes = document.xpath(selector)
    nodes.map { |node| [node["cx"], node["cy"]] }.uniq.size
  end

  def duplicate_context
    ids = commit_ids
    index = ids.index("working on MDR")
    [ids.size, ids.count("working on MDR"),
     ids[index - 1], ids[index + 1]]
  end

  def label_evidence
    rendered = Sirena::Renderer::GitGraph.new.render(duplicate_scene).to_xml
    reference = File.read(
      "spec/fixtures_mermaid/gitgraph/#{duplicate_case}.svg",
    )
    [label_count(rendered, "working on MDR"), reference_commit_count,
     label_count(reference, "working on MDR")]
  end

  def commit_ids
    duplicate_scene.commits.map(&:id)
  end

  it "keeps only Mermaid's later ordinary duplicate declaration" do
    expect(duplicate_context + label_evidence).to eq(
      [13, 1, "new feature for v1.1…", "finishing MDR", 1, 13, 1],
    )
  end

  it "preserves intentional cherry-pick identity reuse" do
    filename = "should_support_cherry_picking_commits-ecf31fda.mmd"
    source = File.read(File.join("spec/mermaid/gitgraph", filename))
    scene = described_class.new.call(Sirena::Parser::GitGraph.new.parse(source))

    expect(scene.commits.map(&:id)).to eq(%w[ZERO A A])
  end
end
