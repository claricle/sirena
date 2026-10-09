# frozen_string_literal: true

require "spec_helper"

RSpec.describe DocSnippets do
  described_class::GUIDES.each do |path|
    described_class.blocks(path).each do |block|
      next if block.lang == "mermaid"

      label = "#{File.basename(path)}:#{block.line}"
      if described_class.skip_reason(block)
        it "skips the #{block.lang} block at #{label}" do
          expect(described_class.skip_reason(block)).not_to be_empty
        end
      elsif described_class::RUNNABLE.include?(block.lang)
        it "runs the #{block.lang} block at #{label}" do
          expect { described_class.run(block) }.not_to raise_error
        end
      else
        it "does not run the #{block.lang || 'plain'} block at #{label}" do
          expect(described_class::RUNNABLE).not_to include(block.lang)
        end
      end
    end
  end

  it "writes output.svg from the quick-start render command" do
    block = described_class.block_containing(
      "sirena render my-first-diagram.mmd", described_class::GUIDES[2]
    )

    expect(described_class.run(block)).to include("output.svg")
  end
end
