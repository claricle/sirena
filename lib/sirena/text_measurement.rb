# frozen_string_literal: true

module Sirena
  # Provides text dimension calculation for layout purposes.
  #
  # This utility calculates approximate text dimensions using character-based
  # estimates, avoiding the need for font metrics libraries. The dimensions
  # are used by the layout engine to size diagram nodes appropriately.
  #
  # @example Basic usage
  #   dims = TextMeasurement.measure("Hello World", font_size: 14)
  #   # => { width: 77.0, height: 14.0 }
  #
  # @example With dimension overrides
  #   dims = TextMeasurement.measure("Text", font_size: 12,
  #                                   width: 100, height: 20)
  #   # => { width: 100, height: 20 }
  class TextMeasurement
    # Average character width as ratio of font size
    AVERAGE_CHAR_WIDTH_RATIO = 0.5

    # Text height as ratio of font size
    HEIGHT_RATIO = 1.0

    # Measures the approximate dimensions of text.
    #
    # @param text [String] the text to measure
    # @param font_size [Numeric] the font size in points
    # @param width [Numeric, nil] optional width override
    # @param height [Numeric, nil] optional height override
    # @return [Hash] hash with :width and :height keys
    #
    # @example Basic measurement
    #   TextMeasurement.measure("Hello", font_size: 14)
    #   # => { width: 35.0, height: 14.0 }
    #
    # @example With overrides
    #   TextMeasurement.measure("Hi", font_size: 14, width: 50)
    #   # => { width: 50, height: 14.0 }
    def self.measure(text, font_size:, width: nil, height: nil)
      calculated_width = calculate_width(text, font_size)
      calculated_height = calculate_height(font_size)

      {
        width: width || calculated_width,
        height: height || calculated_height
      }
    end

    # Calculates the width of text.
    #
    # @param text [String] the text to measure
    # @param font_size [Numeric] the font size in points
    # @return [Float] the calculated width
    def self.calculate_width(text, font_size)
      char_count = text.to_s.length
      avg_char_width = font_size * AVERAGE_CHAR_WIDTH_RATIO
      char_count * avg_char_width
    end

    # Calculates the height of text.
    #
    # @param font_size [Numeric] the font size in points
    # @return [Float] the calculated height
    def self.calculate_height(font_size)
      font_size * HEIGHT_RATIO
    end

    private_class_method :calculate_width, :calculate_height
  end
end
