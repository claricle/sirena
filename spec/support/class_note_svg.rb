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

  def elements(doc, name)
    REXML::XPath.match(doc, ".//*[local-name()='#{name}']")
  end
end
