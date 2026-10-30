# frozen_string_literal: true

require "stringio"
require "spec_helper"

RSpec.describe Sirena::Layout::ElkNotices do
  let(:output) { StringIO.new }
  let(:host) { Logger.new(output, level: Logger::DEBUG) }
  let(:partial) { "elkrb: option elk.direction is partially honoured: x" }
  let(:filtered) { described_class.new(host) }

  around do |example|
    original = Elkrb.logger
    example.run
  ensure
    Elkrb.logger = original
  end

  it "drops the partially-honoured notice for an option Sirena uses" do
    filtered.warn(partial)

    expect(output.string).to eq("")
  end

  it "drops it when it arrives through add or a block" do
    filtered.add(Logger::WARN, partial)
    filtered.warn { partial }

    expect(output.string).to eq("")
  end

  it "forwards a notice for an option elkrb does not honour at all" do
    filtered.warn("elkrb: option elk.foo is accepted but not honoured")

    expect(output.string).to include("accepted but not honoured")
  end

  it "forwards other levels and block-built messages" do
    filtered.error { "boom" }
    filtered.debug("unknown option")

    expect(output.string).to include("boom").and include("unknown option")
  end

  it "forwards other messages that arrive through add or log" do
    filtered.add(Logger::ERROR, "via add")
    filtered.log(Logger::ERROR, "via log")

    expect(output.string).to include("via add").and include("via log")
  end

  it "keeps the wrapped logger's level and formatter" do
    host.level = Logger::ERROR
    filtered.warn("quiet")

    expect([filtered.level, output.string]).to eq([Logger::ERROR, ""])
  end

  describe ".install" do
    it "wraps the logger a host assigned earlier, and only once" do
      Elkrb.logger = host
      described_class.install
      wrapper = Elkrb.logger
      described_class.install

      expect([wrapper.__getobj__, Elkrb.logger]).to eq([host, wrapper])
    end

    context "with a host logger installed behind the filter" do
      let(:graph) do
        { id: "root",
          layoutOptions: { "elk.direction" => "DOWN",
                           "elk.spacing.edgeNode" => 30 },
          children: [{ id: "a", width: 10, height: 10 },
                     { id: "b", width: 10, height: 10 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }] }
      end

      before do
        Elkrb.logger = host
        described_class.install
      end

      it "forwards an unfiltered message and drops the notice" do
        Elkrb.logger.warn(partial)
        Elkrb.logger.warn("elkrb: something else")

        expect(output.string.lines.grep(/partially|something else/).size)
          .to eq(1)
      end

      it "keeps the host logger quiet when Sirena lays a graph out" do
        Sirena::Layout::ElkPlacement.apply(graph)

        expect(output.string).to eq("")
      end
    end
  end

  it "is installed once Sirena's layout is loaded" do
    expect(Elkrb.logger).to be_a(described_class)
  end
end
