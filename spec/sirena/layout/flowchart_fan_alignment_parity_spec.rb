# frozen_string_literal: true

# mmdc places `D & E --> F & G` with dagre's Brandes-Koepf alignment, so
# the two rows are not centred on each other: the parents sit 89.2 apart,
# the children 109.2 apart. Centres are read off the mmdc SVGs.
RSpec.describe Sirena::Layout::Flowchart do
  let(:parents) do
    "flowchart TB\n  D@{ shape: rounded } & E@{ shape: rounded }"
  end
  let(:fan) { "#{parents} --> F@{ shape: rounded } & G@{ shape: rounded }" }
  let(:mixed) { "#{parents} --> F & G@{ shape: rounded }" }
  let(:centres) do
    lambda do |source|
      model = Sirena::Parser::Flowchart.new.parse(source)
      described_class.new.to_graph(model).children
        .to_h { |node| [node.id, node.x + (node.width / 2.0)] }
    end
  end

  it "keeps a fan of rounded nodes in dagre's columns" do
    expect(centres.(fan).values_at("D", "E", "F", "G"))
      .to match([be_within(0.5).of(37.2), be_within(0.5).of(126.4),
                 be_within(0.5).of(27.2), be_within(0.5).of(136.4)])
  end

  it "keeps a fan with a wider first child in dagre's columns" do
    expect(centres.(mixed).values_at("D", "E", "F", "G"))
      .to match([be_within(0.5).of(52.2), be_within(0.5).of(141.4),
                 be_within(0.5).of(42.2), be_within(0.5).of(151.4)])
  end
end
