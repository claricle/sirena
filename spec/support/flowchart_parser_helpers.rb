# frozen_string_literal: true

# Parse helpers shared by the flowchart parser specs. Include with
# `include FlowchartParserHelpers`; the header lets a spec prepend its own
# lines before the statement under test.
module FlowchartParserHelpers
  def parse_flowchart(source, header: "flowchart TD\n")
    Sirena::Parser::FlowchartParser.new.parse("#{header}#{source}\n")
  end

  def edge_tuples(source)
    parse_flowchart(source).edges
      .map { |e| [e.source_id, e.target_id, e.label, e.arrow_type] }
  end

  def edge_links(source)
    parse_flowchart(source).edges.map { |e| "#{e.source_id}>#{e.target_id}" }
  end
end
