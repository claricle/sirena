# frozen_string_literal: true

require "spec_helper"

# A mindmap node points at its parent, so the YAML dump the shared parity
# examples compare (spec/support/native_parity.rb) never terminates. This
# compares the model as plain data instead.
module MindmapParity
  DIRECTORY = "mindmap"

  module_function

  def dump(node)
    {
      id: node.id, content: node.content, level: node.level,
      shape: node.shape, icon: node.icon, classes: node.classes,
      parent: node.parent&.id, children: node.children.map { |c| dump(c) }
    }
  end

  def outcome(source, native:)
    NativeParity.with_native(native) do
      diagram = NativeParity.parser_class(DIRECTORY).new.parse(source)
      [:ok, diagram.root && dump(diagram.root), diagram.nodes.map { dump(_1) }]
    end
  rescue Sirena::Parser::ParseError => e
    [:error, e.message]
  end

  def same?(source)
    outcome(source, native: true) == outcome(source, native: false)
  end

  def sources
    NativeParity.fixtures(DIRECTORY).map { |path| File.read(path) }
  end

  def parslet_accepts
    sources.count { |source| outcome(source, native: false).first == :ok }
  end
end

RSpec.describe Sirena::Parser::Native, ".parse parity (mindmap)" do
  it "has fixtures to compare" do
    expect(NativeParity.fixtures("mindmap")).not_to be_empty
  end

  it "answers natively for every fixture Parslet accepts" do
    skip "parsanol engine absent" unless described_class.available?

    expect(NativeParity.native_answers("mindmap"))
      .to be >= MindmapParity.parslet_accepts
  end

  NativeParity.fixtures("mindmap").each do |path|
    it "agrees with Parslet on #{File.basename(path)}" do
      expect(MindmapParity.same?(File.read(path))).to be(true)
    end
  end

  edge_sources = [
    "mindmap",
    "mindmap\n",
    "mindmap\n\n",
    "  mindmap  \n  root",
    "mindmap\r\n  root\r\n    a\r\n    b\r\n",
    "mindmap root",
    "mindmap  root\n    a",
    "mindmap%% c\n  root",
    "mindmap %% c\n  root",
    "mindmapx\n  root",
    "mindmap_1\n  root",
    "mindmap\n  root\n    a\n    b\n      c\n    d",
    "mindmap\n  root\n    a\n  b",
    "mindmap\n    root\n  a",
    "mindmap\n  root\n\ta\n\t\tb",
    "mindmap\n  root((Central))\n    a",
    "mindmap\n  id((Central idea))\n    a",
    "mindmap\n  root))Bang((\n    a",
    "mindmap\n  root)Cloud(\n    a",
    "mindmap\n  root{{Hex}}\n    a",
    "mindmap\n  root[Square]\n    a",
    "mindmap\n  root[\"Quoted [x]\"]\n    a",
    "mindmap\n  root[]\n    a",
    "mindmap\n  root(Round)\n    a",
    "mindmap\n  root(\"q)\")\n    a",
    "mindmap\n  root(\n    multi\n    %% hidden\n    line\n  )\n    a",
    "mindmap\n  root(\"x\n  %% gone \"\n  y\")",
    "mindmap\n  root(%% keep)\n    a",
    "mindmap\n  root( \n %% hidden\nz)",
    "mindmap\n  root(a\n  %%{init}\n  b)",
    "mindmap\n  root\n    a(open\n    b",
    "mindmap\n  root\n    a[open\n    b",
    "mindmap\n  root\n    ::icon(fa fa-book)\n    :::cls1 cls2",
    "mindmap\n  root\n    a\n      ::icon(fa)\n      :::x",
    "mindmap\n  ::icon(fa)\n  root",
    "mindmap\n  :::x\n  root",
    "mindmap\n  root\n    a: b",
    "mindmap\n  root\n    é日本\n      ü",
    "mindmap\n  root((é))\n    [日本]",
    "mindmap\n  root %% tail\n    a [x] %% tail\n    b((c)) %% tail",
    "mindmap\n  %% comment\n  root\n\n    %% another\n    a\n",
    "mindmap\n  root\n  other",
    "mindmap\n  root\n    a   \n    b\t",
    "mindmap\n  root\n    a\n   ",
    "Mindmap\n  root",
    "mindmap\n  root;\n    a",
    "%% lead\nmindmap\n  root",
    "",
    "   ",
  ]

  edge_sources.each do |source|
    it "agrees on #{source.inspect}" do
      expect(MindmapParity.same?(source)).to be(true)
    end
  end
end
