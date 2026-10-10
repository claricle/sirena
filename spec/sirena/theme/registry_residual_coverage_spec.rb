# frozen_string_literal: true

require "spec_helper"
require "sirena/theme/registry"

RSpec.describe Sirena::Theme::Registry do
  let(:theme) { Sirena::Theme.new(name: "custom") }
  let(:builtin_dir) do
    source = described_class.method(:load_builtin_themes).source_location.first
    File.join(File.dirname(source), "builtin")
  end

  around do |example|
    saved_themes = described_class.list.to_h do |name|
      [name, described_class.get(name)]
    end
    example.run
  ensure
    described_class.clear
    saved_themes&.each { |name, theme| described_class.register(name, theme) }
  end

  before do
    described_class.clear
    described_class.register(:custom, theme)
    allow(Dir).to receive(:exist?).with(builtin_dir).and_return(false)
  end

  it "preserves registered themes when the built-in directory is missing" do
    described_class.load_builtin_themes
    expect([described_class.list, described_class.get(:custom)])
      .to eq([[:custom], theme])
  end
end
