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

  it "centres a parent over a row of two children" do
    found = builder.placed("TD", [%w[Parent Left], %w[Parent Right]])
    row_centre = (found["Left"].x + found["Right"].x + found["Right"].width) / 2

    expect(found["Parent"].center_x).to be_within(0.01).of(row_centre)
  end
end
