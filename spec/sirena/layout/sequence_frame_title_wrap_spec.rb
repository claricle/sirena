# frozen_string_literal: true

require "spec_helper"

# Numbers measured on mmdc output (cases 040 and 042), view box origin
# (-50, -10) moved to 0.
RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  let(:wide) do
    layout_scene("Service-->DB: connect\ncritical Establish a connection to " \
                 "the DB\nService-->DB: x\nend")
  end
  let(:short) do
    layout_scene("Service-->DB: connect\nloop L\nService-->DB: x\nend")
  end

  it "wraps a long title at the title area, brackets included" do
    expect(wide.frames.first.title_lines)
      .to eq(["[Establish a connection", "to the DB]"])
  end

  it "keeps a short title on one line" do
    expect(short.frames.first.title_lines).to eq(["[L]"])
  end

  it "grows the frame and canvas by 14 for the second line" do
    plain = layout_scene("Service-->DB: connect\ncritical Establish\n" \
                         "Service-->DB: x\nend")

    expect([wide.frames.first.height - plain.frames.first.height,
            wide.height - plain.height]).to eq([14, 14])
  end
end
