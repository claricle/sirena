# frozen_string_literal: true

# mmdc lines a chain of different-sized nodes up on their centres:
# `1Function-->2URL` has both centred on x 73.2.
RSpec.describe Sirena::Layout::Flowchart::RowCentering do
  let(:builder) { FlowchartSceneBuilder }

  it "centres a narrower node under a wider one in TD" do
    found = builder.placed("TD", [%w[WideNodeName Narrow]])

    expect(found["Narrow"].center_x)
      .to be_within(0.01).of(found["WideNodeName"].center_x)
  end

  it "centres a shorter node beside a taller one in LR" do
    found = builder.placed("LR", [%w[A B]],
                           labels: { "A" => "one<br>two<br>three" })

    expect(found["B"].center_y).to be_within(0.01).of(found["A"].center_y)
  end

  # Pinned mmdc 11.12.0 puts Parent 2.227 left of the children's row centre
  # (Brandes-Koepf), not on it; text widths differ from mmdc's by ~2px.
  it "sets a parent just left of its two children's row centre, as mmdc" do
    found = builder.placed("TD", [%w[Parent Left], %w[Parent Right]])
    row_centre = (found["Left"].x + found["Right"].x + found["Right"].width) / 2

    expect(found["Parent"].center_x - row_centre).to be_within(0.3).of(-2.227)
  end
end
