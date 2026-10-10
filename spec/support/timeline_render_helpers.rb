# frozen_string_literal: true

require "rexml/document"
require_relative "timeline_scene_helpers"

# Renders timeline source to a parsed SVG document.
module TimelineRenderHelpers
  include TimelineSceneHelpers

  def render_doc(source)
    scene = lay_out(source)
    xml = Sirena::Renderer::Timeline.new.render(scene).to_xml
    REXML::Document.new(xml)
  end

  def nodes(doc, path)
    REXML::XPath.match(doc, path)
  end

  def attrs(doc, path, name)
    nodes(doc, path).map { |node| node.attributes[name] }
  end
end
