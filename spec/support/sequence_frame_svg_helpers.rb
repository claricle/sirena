# frozen_string_literal: true

require "rexml/document"

# Reads boxes, frames and message rows back out of rendered sequence SVG.
module SequenceFrameSvgHelpers
  def svg_document(body)
    REXML::Document.new(render_sequence(body))
  end

  def svg_group(doc, id)
    REXML::XPath.first(doc, "//*[@id='#{id}']")
  end

  # [x, y, width, height] of the first rect inside `node`
  def rect_box(node)
    rect = REXML::XPath.first(node, ".//*[local-name()='rect']")
    %w[x y width height].map { |name| rect.attributes[name].to_f }
  end

  def participant_boxes(doc, ids)
    ids.map { |id| rect_box(svg_group(doc, "participant-#{id}")) }
  end

  def message_y(doc, index)
    line = REXML::XPath.first(svg_group(doc, "message-#{index}"), ".//line")
    line.attributes["y1"].to_f
  end

  def group_texts(node)
    REXML::XPath.match(node, ".//*[local-name()='text']").map do |text|
      text.texts.map(&:value).join
    end
  end

  def encloses?(outer, inner)
    ox, oy, ow, oh = outer
    ix, iy, iw, ih = inner
    ox <= ix && oy <= iy && ox + ow >= ix + iw && oy + oh >= iy + ih
  end
end
