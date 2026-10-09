# frozen_string_literal: true

require_relative "doc_snippets"

# Extracts the diagrams shown in the `[source,mermaid]` blocks of the docs.
#
# A block that shows a "Good" and a "Less clear" version side by side holds
# several diagrams; each one is rendered on its own, so a block is split at a
# blank line followed by a `%%` comment when what follows starts a new diagram.
module DocMermaidBlocks
  Diagram = Struct.new(:file, :key, :source)

  DOCS = File.expand_path("../../docs", __dir__)

  HEADER = /\A(?:C4\w+|classDiagram\S*|erDiagram|graph|flowchart\S*|gantt|gitGraph|kanban|mindmap|
    packet(?:-beta)?|pie|quadrantChart|radar(?:-beta)?|sankey(?:-beta)?|sequenceDiagram|
    stateDiagram\S*|timeline|treemap\S*|journey|xychart\S*|requirementDiagram|block\S*|
    architecture\S*|info|error)\b/x

  module_function

  def files
    Dir.glob(File.join(DOCS, "**/*.adoc")).sort
  end

  # Marker lines the independent count looks for, so a block the extractor
  # fails to see shows up as a count mismatch.
  def marker_count
    files.sum { |f| File.foreach(f).count { |l| l.chomp.match?(/\A\[source,\s*mermaid\]\z/) } }
  end

  def block_count
    files.sum { |f| DocSnippets.blocks(f).count { |b| b.lang == "mermaid" } }
  end

  def diagrams
    files.flat_map { |file| file_diagrams(file) }
  end

  def file_diagrams(file)
    lines = File.read(file).lines(chomp: true)
    relative = file.delete_prefix("#{File.dirname(DOCS)}/")
    seen = Hash.new(0)
    DocSnippets.blocks(file).select { |b| b.lang == "mermaid" }.flat_map do |block|
      heading = heading_before(lines, block.line)
      seen[heading] += 1
      split(block.body).each_with_index.map do |source, part|
        suffix = ".#{part + 1}" if part.positive? || split(block.body).size > 1
        Diagram.new(relative, "#{heading} ##{seen[heading]}#{suffix}", source)
      end
    end
  end

  def heading_before(lines, marker_line)
    lines.first(marker_line).reverse.find { |l| l.match?(/\A=+ /) }.to_s.sub(/\A=+ /, "")
  end

  def split(body)
    body.split(/\n{2,}(?=%%)/).each_with_object([]) do |chunk, parts|
      if parts.empty? || header?(chunk)
        parts << chunk
      else
        parts[-1] = "#{parts.last}\n\n#{chunk}"
      end
    end
  end

  def header?(chunk)
    first = chunk.lines.map(&:strip).find { |l| !l.empty? && !l.start_with?("%%") }
    first.to_s.match?(HEADER)
  end
end
