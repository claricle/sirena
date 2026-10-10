# frozen_string_literal: true

require "rexml/document"

# Reads the SVG the engine draws for a class diagram.
module ClassNoteSvg
  module_function

  def document(source)
    REXML::Document.new(Sirena::Engine.new.render(source))
  end

  def texts(source)
    elements(document(source), "text").map { |node| node.texts.join }
  end

  def values(source, name, attribute)
    elements(document(source), name).map { |node| node.attributes[attribute] }
  end

  # The groups the engine draws for notes
  def notes(source)
    elements(document(source), "g").select { |group| note?(group) }
  end

  def note?(group)
    group.attributes["id"].to_s.start_with?("note-")
  end

  def group(source, id)
    elements(document(source), "g").find do |item|
      item.attributes["id"] == id
    end
  end

  def group_ids(source)
    elements(document(source), "g").map { |item| item.attributes["id"] }
  end

  def rect(source, id)
    elements(group(source, id), "rect").first.attributes
  end

  # Whether the rect `inner` lies wholly inside the rect `outer`
  def contained?(inner, outer)
    horizontal = span(inner, "x", "width")
    vertical = span(inner, "y", "height")
    within?(horizontal, span(outer, "x", "width")) &&
      within?(vertical, span(outer, "y", "height"))
  end

  def span(rect, start, size)
    [rect[start].to_f, rect[start].to_f + rect[size].to_f]
  end

  def within?(inner, outer)
    inner.first >= outer.first && inner.last <= outer.last
  end

  def elements(doc, name)
    REXML::XPath.match(doc, ".//*[local-name()='#{name}']")
  end
end
