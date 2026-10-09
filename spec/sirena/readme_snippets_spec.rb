# frozen_string_literal: true

require "spec_helper"

RSpec.describe DocSnippets do
  it "finds the source blocks" do
    expect(described_class.blocks).not_to be_empty
  end

  it "skips only blocks that are named with a reason" do
    expect(described_class.skipped_keys_without_block).to eq([])
  end

  described_class.blocks.each do |block|
    if described_class.skip_reason(block)
      it "skips the #{block.lang || 'plain'} block at line #{block.line}" do
        expect(described_class.skip_reason(block)).not_to be_empty
      end
    else
      it "runs the #{block.lang} block at line #{block.line}" do
        expect { described_class.run(block) }.not_to raise_error
      end
    end
  end

  it "writes output.svg from the programmatic example" do
    block = described_class.blocks.find { |b| b.lang == "ruby" && b.body.include?("Sirena.render") }

    expect(described_class.run(block)).to include("output.svg")
  end

  it "writes output.svg from the render command" do
    block = described_class.blocks.find { |b| b.body.start_with?("sirena render") }

    expect(described_class.run(block)).to include("output.svg")
  end

  it "writes the batch outputs into output_dir" do
    block = described_class.blocks.find { |b| b.body.start_with?("sirena batch") }

    expect(described_class.run(block).grep(%r{\Aoutput_dir/.*\.svg\z})).not_to be_empty
  end
end
