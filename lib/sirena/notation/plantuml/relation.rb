# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A relation line, kept the way it was written.
      #
      # `left` and `right` are the class names on either side of the arrow.
      # `head` is the side the marker or arrowhead sits on, :left or :right,
      # or nil for a plain `--`. `kind` is :extension, :implementation,
      # :association, :aggregation or :composition. The multiplicities and
      # the label are the quoted and `: text` parts, or nil.
      Relation = Data.define(:left, :right, :kind, :head,
                             :left_multiplicity, :right_multiplicity, :label)
    end
  end
end
