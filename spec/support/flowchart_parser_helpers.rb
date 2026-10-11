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

  def node_ids(source)
    parse_flowchart(source).nodes.map(&:id)
  end

  # The corpus cases that exercise `&` grouping. Callable from a describe
  # body as well as from an example, so the spec can both generate one
  # example per case and assert the bucket is not empty.
  AMP_BUCKET = %w[
    flow_node_data_spec-b671d90d
    flow_node_data_spec-81a45067
    flow_node_data_spec-f80854cb
    flow_node_data_spec-930a0e8f
    flow_node_data_spec-dcd14ebd
    flow_node_data_spec-738054ca
    flow_node_data_spec-65204278
    flow_node_data_spec-8d537ea3
    flow_node_data_spec-eaf9026c
    flow_node_data_spec-42630695
    flow_node_data_spec-fea71e9f
    flow_node_data_spec-2cd7940f
    flow_node_data_spec-8dedd493
    flow_node_data_spec-6e31de6c
  ].freeze

  def self.amp_bucket_paths(dir)
    AMP_BUCKET.map { |id| File.join(dir, "#{id}.mmd") }
  end

  def amp_bucket_paths(dir)
    FlowchartParserHelpers.amp_bucket_paths(dir)
  end
end
