# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # The mapping a nested <svg> imposes on its children: x/y/width/height
    # plus viewBox/preserveAspectRatio, against the parent's [width, height].
    class NestedViewport
      ALIGNMENT = { "Min" => 0.0, "Mid" => 0.5, "Max" => 1.0 }.freeze

      def initialize(node, parent_size)
        @node = node
        @parent_size = parent_size
        @offset = [measure("x", 0) || 0.0, measure("y", 1) || 0.0]
        @size = [measure("width", 0) || parent_size[0],
                 measure("height", 1) || parent_size[1]]
        @view_box = node["viewBox"].to_s.scan(Matrix::NUMBER).map(&:to_f)
      end

      # Child space to parent space.
      def matrix
        return Matrix.translate(*@offset) unless view_box?

        align, mode = aspect_ratio
        align == "none" ? stretch : fit(align, mode)
      end

      # The [width, height] percentages inside resolve against.
      def size
        view_box? ? @view_box.last(2) : @size
      end

      private

      def view_box?
        @view_box.size == 4 && @size.all?
      end

      def measure(name, axis)
        text = @node[name]
        return nil if text.nil?

        value = text[Matrix::NUMBER]&.to_f
        reference = @parent_size[axis]
        text.include?("%") && reference ? reference * value / 100 : value
      end

      def aspect_ratio
        align, mode = @node["preserveAspectRatio"].to_s.split
        [align || "xMidYMid", mode || "meet"]
      end

      # preserveAspectRatio="none": each axis scales on its own.
      def stretch
        width, height = @size
        origin_x, origin_y, view_width, view_height = @view_box
        Matrix.new([width / view_width, 0, 0, height / view_height,
                    @offset[0] - (origin_x * width / view_width),
                    @offset[1] - (origin_y * height / view_height)])
      end

      def fit(align, mode)
        scale = fit_scale(mode)
        Matrix.new([scale, 0, 0, scale,
                    fit_translation(0, align[1, 3], scale),
                    fit_translation(1, align[5, 3], scale)])
      end

      def fit_scale(mode)
        factors = [@size[0] / @view_box[2], @size[1] / @view_box[3]]
        mode == "slice" ? factors.max : factors.min
      end

      def fit_translation(axis, alignment, scale)
        spare = @size[axis] - (@view_box[2 + axis] * scale)
        @offset[axis] + (ALIGNMENT.fetch(alignment) * spare) -
          (@view_box[axis] * scale)
      end
    end
  end
end
