# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart::EdgeOrder do
  def level(ids, edges)
    { children: ids.map { |id| { id: id } },
      edges: edges.map { |from, to| { sources: [from], targets: [to] } } }
  end

  def order(ids, edges)
    described_class.apply(level(ids, edges))[:children].map { |b| b[:id] }
  end

  it "lists boxes in the order their edges name them" do
    expect(order(%w[B b a], [%w[a B], %w[b B]])).to eq(%w[a B b])
  end

  it "leaves a box without an edge in its own slot" do
    expect(order(%w[x b a], [%w[a b]])).to eq(%w[x a b])
  end

  it "keeps the order of a level without edges" do
    expect(order(%w[c a b], [])).to eq(%w[c a b])
  end
end
