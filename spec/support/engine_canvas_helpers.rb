# frozen_string_literal: true

require "rexml/document"

# Renders Mermaid source through the Engine and returns the parsed <svg> root.
module EngineCanvasHelpers
  def canvas(source)
    REXML::Document.new(Sirena::Engine.new.render(source)).root
  end
end
