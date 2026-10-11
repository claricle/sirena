# frozen_string_literal: true

require "nokogiri"

# Geometry read from an mmdc reference SVG under spec/fixtures_mermaid/mindmap.
module MindmapReference
  DIRECTORY = File.expand_path("../fixtures_mermaid/mindmap", __dir__)
  NODE_PATH = %r{\AM(-?[\d.]+) (-?[\d.]+)}
  ROUNDED_CORNER = "q0,-5 5,-5"

  module_function

  def document(name)
    path = Dir[File.join(DIRECTORY, "#{name}.svg")].first
    Nokogiri::XML(File.read(path)).tap(&:remove_namespaces!)
  end

  # @return [Array<Hash>] :id, :centre of each node group in document order
  def nodes(name)
    document(name).xpath("//g[contains(@class, 'mindmap-node')]").map do |group|
      { id: group["id"].delete_prefix("node_"),
        centre: translation(group).split(",").map(&:to_f),
        size: rounded_size(group.at_xpath("path")) }
    end
  end

  def translation(group)
    group["transform"][/translate\(([^)]*)\)/, 1]
  end

  # @return [Array<Array<String>>] [parent id, child id] per edge
  def edges(name)
    document(name).xpath("//g[@class='edgePaths']/path").map do |path|
      path["id"].delete_prefix("edge_").split("_")
    end
  end

  # @return [Array<Array<Float>>] the numbers of each edge's path, in pairs
  def edge_paths(name)
    document(name).xpath("//g[@class='edgePaths']/path").map do |path|
      path["d"].scan(/-?\d+\.?\d*/).map(&:to_f).each_slice(2).to_a
    end
  end

  # @return [Array<Float>] viewBox x, y, width, height
  def view_box(name)
    document(name).root["viewBox"].split.map(&:to_f)
  end

  # Width and height of a rounded rectangle node, or nil for other shapes.
  def rounded_size(path)
    outline = path ? path["d"].to_s : ""
    corner = outline.match(NODE_PATH)
    return unless corner && outline.include?(ROUNDED_CORNER)

    [-2 * corner[1].to_f, (2 * corner[2].to_f.abs) + 10]
  end
end
