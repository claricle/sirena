# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Renderer::Architecture do
  # spec/fixtures_mermaid/architecture/004_*.svg draws "?" for this icon.
  let(:source) do
    "architecture-beta\n  service unknown(iconnamedoesntexist)[Unknown Icon]\n"
  end
  let(:doc) { REXML::Document.new(Sirena::Engine.new.render(source)) }

  it "draws ? for an icon without a pack" do
    texts = REXML::XPath.match(doc, "//*[local-name()='text']").map do |node|
      node.texts.map(&:value).join
    end

    expect(texts).to include("?")
  end
end
