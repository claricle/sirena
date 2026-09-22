# frozen_string_literal: true

# Parse helpers shared by the flowchart parser specs. Include with
# `include FlowchartParserHelpers`; the header lets a spec prepend its own
# lines before the statement under test.
module FlowchartParserHelpers
  def parse_flowchart(source, header: "flowchart TD\n")
    Sirena::Parser::Flowchart.new.parse("#{header}#{source}\n")
  end

  def edge_tuples(source)
    parse_flowchart(source).edges
      .map { |e| [e.source_id, e.target_id, e.label, e.arrow_type] }
  end

  def edge_links(source)
    parse_flowchart(source).edges.map { |e| "#{e.source_id}>#{e.target_id}" }
  end

  # The corpus cases that exercise `&` grouping. Callable from a describe
  # body as well as from an example, so the spec can both generate one
  # example per case and assert the bucket is not empty.
  AMP_BUCKET = /\A\d+_parser_should_(handle_basic_shape_data_statements_with_|
                                     be_possible_to_use_syntax_to_add_labels_on_multi)/x

  def self.amp_bucket_paths(dir)
    Dir[File.join(dir, "*.mmd")]
      .select { |f| File.basename(f).match?(AMP_BUCKET) }
  end

  def amp_bucket_paths(dir)
    FlowchartParserHelpers.amp_bucket_paths(dir)
  end
end
