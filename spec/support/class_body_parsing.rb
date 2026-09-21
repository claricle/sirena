# frozen_string_literal: true

# Parses a class body and returns the first entity.
module ClassBodyParsing
  def parse_class(body)
    described_class.new.parse("classDiagram\nclass A {\n#{body}\n}\n").entities.first
  end
end
