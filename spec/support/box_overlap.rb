# frozen_string_literal: true

# Whether two positioned boxes (anything with x, y, width and height)
# share interior area; boxes that only touch do not overlap.
module BoxOverlap
  module_function

  def overlap?(first, second)
    spans?(first.x, first.width, second.x, second.width) &&
      spans?(first.y, first.height, second.y, second.height)
  end

  def spans?(start, size, other_start, other_size)
    start < other_start + other_size && other_start < start + size
  end
end
