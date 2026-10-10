# frozen_string_literal: true

# Reads timeline cards as plain numbers so a spec can compare them with the
# values mmdc draws, rounded past float noise.
module TimelineSceneHelpers
  def box(card)
    [card.x, card.y, card.width, card.height].map { |value| value.round(2) }
  end

  def drop_line(card)
    line = card.connector
    [line.x1, line.y1, line.x2, line.y2].map { |value| value.round(2) }
  end

  def cards_of(scene, kind)
    scene.cards.select { |card| card.kind == kind }
  end

  def lay_out(source)
    diagram = Sirena::Parser::Timeline.new.parse(source)
    Sirena::Layout::Timeline.new.call(diagram)
  end

  def period(name, *events)
    { name: name, events: events }
  end
end
