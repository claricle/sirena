# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Native, ".parse parity (info)" do
  it_behaves_like "native corpus parity", "info"

  it_behaves_like "native edge parity", "info", [
    "info",
    "info\n",
    "info showInfo",
    "info  showInfo  ",
    "info\n  showInfo",
    "info\nshowInfo\nshowInfo",
    "info showInfo\nshowInfo",
    "info other",
    "info\nother",
    "info showInfoX",
    "Info",
    "info %% c\n",
    "info;\n",
    "%% x\ninfo showInfo ;",
    "",
  ]
end
