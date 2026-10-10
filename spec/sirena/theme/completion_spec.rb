# frozen_string_literal: true

require "spec_helper"
require "sirena/theme/completion"

RSpec.describe Sirena::Theme::Completion do
  include PartialThemeRenders

  let(:default) { Sirena::Theme::Registry.get(:default) }
  let(:default_firsts) do
    %i[flow xy timeline_fill].map { |name| default.colors.palette(name, 0) }
  end
  let(:partial) do
    Sirena::Theme.new(name: "mine", colors: { background: "#101010" })
  end
  let(:completed) { described_class.call(partial) }

  it "keeps the colours the theme sets" do
    expect([completed.name, completed.colors.background])
      .to eq(["mine", "#101010"])
  end

  it "takes every unset colour and palette from the default theme" do
    unset = Sirena::Theme::ColorPalette.attributes.keys - [:background]

    expect(unset.map { |key| completed.colors.public_send(key) })
      .to eq(unset.map { |key| default.colors.public_send(key) })
  end

  it "leaves the caller's theme partial" do
    completed

    expect(partial.colors.card_text).to be_nil
  end

  it "returns a theme that sets every colour unchanged" do
    expect(described_class.call(Sirena::Theme::Registry.get(:dark)))
      .to be(Sirena::Theme::Registry.get(:dark))
  end

  it "lets a partial theme draw each palette diagram in default colours" do
    drawn = partial_theme_fills.zip(default_firsts).map do |fills, colour|
      fills.include?(colour)
    end

    expect(drawn).to eq([true, true, true])
  end

  it "uses the default theme when there is none" do
    expect(described_class.call(nil)).to be(default)
  end
end
