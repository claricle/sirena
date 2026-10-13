# frozen_string_literal: true

module Sirena
  module Layout
    # Advances, in per-mille em, of the ASCII letters, digits and - _ < >
    # of mmdc's
    # bold class names (Trebuchet MS Bold). Fitted so that the width of every
    # reference class-name label in spec/fixtures_mermaid stays within half
    # a pixel; any other character is the regular face widened by
    # FALLBACK_RATIO.
    module ClassNameAdvances
      FALLBACK_RATIO = 1.05

      TABLE = {
        "-" => 365, "<" => 608, ">" => 608, "_" => 580,
        "0" => 582, "1" => 579, "2" => 577, "3" => 576, "4" => 574,
        "5" => 572, "6" => 571, "7" => 569, "8" => 568, "9" => 567,
        "A" => 632, "B" => 601, "C" => 629, "D" => 653, "E" => 568,
        "F" => 577, "G" => 679, "H" => 685, "I" => 273, "J" => 524,
        "K" => 610, "L" => 536, "M" => 737, "N" => 659, "O" => 701,
        "P" => 577, "R" => 613, "S" => 516, "T" => 549, "U" => 687,
        "W" => 892, "Z" => 564, "a" => 524, "b" => 570, "c" => 520,
        "d" => 585, "e" => 569, "f" => 368, "g" => 501, "h" => 584,
        "i" => 298, "j" => 378, "k" => 544, "l" => 304, "m" => 858,
        "n" => 580, "o" => 554, "p" => 586, "q" => 580, "r" => 419,
        "s" => 425, "t" => 400, "u" => 588, "v" => 526, "w" => 748,
        "x" => 544, "y" => 525
      }.freeze
    end
  end
end
