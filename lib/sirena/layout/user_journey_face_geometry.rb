# frozen_string_literal: true

module Sirena
  module Layout
    # Where a task's face, eyes and mouth sit on the canvas. The face's height
    # follows the score; mmdc draws the eyes a third of the radius off centre
    # and the mouth a few pixels below it.
    module UserJourneyFaceGeometry
      FACE_RADIUS = 15
      FACE_TOP = 300
      FACE_STEP = 30
      SMILE_OFFSET = 2
      FROWN_OFFSET = 7
      FLAT_HALF_WIDTH = 5
      MOUTH_OUTER = 7.5
      MOUTH_INNER = 6.818

      private

      def task_face(box, score)
        center_x = box.x + (box.width / 2.0)
        center_y = FACE_TOP + ((5 - score) * FACE_STEP)
        UserJourney::Face.new(
          center_x: center_x, center_y: center_y, radius: FACE_RADIUS,
          eyes: face_eyes(center_x, center_y),
          mouth: face_mouth(center_x, center_y, score)
        )
      end

      def face_eyes(center_x, center_y)
        [-1, 1].map do |side|
          UserJourney::FacePoint.new(
            x: center_x + (side * FACE_RADIUS / 3.0),
            y: center_y - (FACE_RADIUS / 3.0),
          )
        end
      end

      def face_mouth(center_x, center_y, score)
        return flat_mouth(center_x, center_y) if score == 3

        smile = score > 3
        offset = smile ? SMILE_OFFSET : FROWN_OFFSET
        UserJourney::FaceMouth.new(
          path: arc_path(center_x, center_y + offset, smile ? 1 : -1),
        )
      end

      def flat_mouth(center_x, center_y)
        row = center_y + FROWN_OFFSET
        UserJourney::FaceMouth.new(
          line: UserJourney::Line.new(
            x1: center_x - FLAT_HALF_WIDTH, y1: row,
            x2: center_x + FLAT_HALF_WIDTH, y2: row
          ),
        )
      end

      # A smile starts at the right end and sweeps over the top; a frown
      # starts at the left end.
      def arc_path(center_x, center_y, direction)
        row = coord(center_y)
        at = ->(offset) { "#{coord(center_x + (direction * offset))},#{row}" }
        "M#{at.(MOUTH_OUTER)}#{arc(MOUTH_OUTER, 1)},#{at.(-MOUTH_OUTER)}" \
          "L#{at.(-MOUTH_INNER)}#{arc(MOUTH_INNER, 0)},#{at.(MOUTH_INNER)}Z"
      end

      def arc(radius, sweep)
        "A#{radius},#{radius},0,1,#{sweep}"
      end

      def coord(value)
        rounded = value.round(3)
        rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
      end
    end
  end
end
