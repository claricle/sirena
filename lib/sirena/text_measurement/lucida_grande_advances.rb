# frozen_string_literal: true

# Horizontal advance widths in per-mille em of Lucida Grande Regular and
# Bold for Basic Latin (U+0020 to U+007E), read from the hmtx table of the
# face Java's "SansSerif" resolves to on macOS, and so the face a PlantUML
# JAR run there measures text with. Advances are numeric facts about a
# glyph, not a copy of any font.
module Sirena
  class TextMeasurement
    module LucidaGrandeAdvances
      REGULAR_DATA = <<~RUNS
        316 316 374 632 632 668 697 229 325 325 482 795 316 579 316 524
        632 632 632 632 632 632 632 632 632 632 316 316 795 795 795 422
        858 690 575 692 749 542 536 723 735 288 311 653 533 861 739 777
        553 777 632 539 632 693 654 855 626 623 604 325 524 325 632 500
        614 552 629 512 629 557 368 624 621 289 304 584 289 934 621 614
        629 629 409 510 374 621 518 771 613 522 573 325 374 325 632
      RUNS

      BOLD_DATA = <<~RUNS
        330 313 452 660 660 783 745 247 371 371 466 795 247 639 247 565
        660 660 660 660 660 660 660 660 660 660 247 247 795 795 795 497
        858 736 630 712 793 601 574 746 780 332 418 710 582 908 769 823
        613 824 690 571 690 736 699 904 667 687 645 371 565 371 660 500
        639 588 663 532 663 586 415 660 657 325 333 633 325 970 657 639
        663 663 455 565 405 657 593 863 591 583 591 371 386 371 795
      RUNS

      REGULAR = REGULAR_DATA.split.each_with_index.to_h do |value, index|
        [0x20 + index, value.to_i]
      end.freeze

      BOLD = BOLD_DATA.split.each_with_index.to_h do |value, index|
        [0x20 + index, value.to_i]
      end.freeze
    end
  end
end
