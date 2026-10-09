# frozen_string_literal: true

require "spec_helper"

module ExampleReadmeMermaidBlocks
  ROOT = File.expand_path("../..", __dir__)
  READMES = Dir.glob(File.join(ROOT, "examples/*/README.adoc")).sort.freeze
  MARKER = /\A\[source,\s*mermaid\][[:space:]]*\z/
  INCLUDE = /\Ainclude::(.+\.mmd)\[\]\z/

  module_function

  def blocks
    READMES.flat_map { |readme| DocSnippets.blocks(readme) }
      .select { |block| block.lang == "mermaid" }
  end

  def marker_count
    READMES.sum { |readme| File.foreach(readme).count { |line| line.match?(MARKER) } }
  end

  def source(block)
    include_path = INCLUDE.match(block.body.strip)&.[](1)
    return block.body unless include_path

    target = File.expand_path(include_path, File.dirname(block.path))
    return File.read(target) if File.file?(target)

    raise IOError, "#{block.path}:#{block.line}: missing Mermaid include #{include_path}"
  end

  def label(block)
    "#{block.path.delete_prefix("#{ROOT}/")}:#{block.line}"
  end
end

RSpec.describe ExampleReadmeMermaidBlocks do
  it "extracts all 67 Mermaid source markers" do
    expect([described_class.marker_count, described_class.blocks.size]).to eq([67, 67])
  end

  it "reports a missing relative include with its source location" do
    path = File.join(described_class::ROOT, "examples/error/README.adoc")
    block = DocSnippets::Block.new(path, 12, "mermaid", "include::missing.mmd[]")

    expect { described_class.source(block) }
      .to raise_error(IOError, /README\.adoc:12: missing Mermaid include missing\.mmd/)
  end

  described_class.blocks.each do |block|
    it "renders #{described_class.label(block)} as SVG" do
      source = described_class.source(block)

      expect(Sirena.render(source)).to match(/\A\s*<svg\b.*<\/svg>\s*\z/m)
    end
  end
end
