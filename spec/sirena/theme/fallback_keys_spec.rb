# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::ColorPalette do
  include ThemeFallbacks

  # One key, several fallback colours: each needs its own role first.
  let(:awaiting_roles) { %i[axis_line border_color grid_line text text_color] }
  let(:asked_for) { theme_fallbacks.keys - awaiting_roles }

  let(:carried) do
    %i[border edge_color field_background field_border field_text
       group_background highlight node_bg node_text note_fill section_bg
       title_text]
  end

  # Keys whose last fallback was deleted from lib/: the colour it drew.
  let(:pinned) do
    { border: "#d1d5db", field_background: "#efefef",
      field_border: "#000000", field_text: "#000000", node_text: "#FFFFFF",
      title_text: "#000000" }
  end

  it "defines every colour a renderer asks the theme for" do
    unset = builtin_themes.flat_map do |theme|
      asked_for.reject { |key| theme.colors.public_send(key) }
    end
    expect(unset).to be_empty
  end

  it "carries each key with a remaining fallback at that fallback's colour" do
    still_fallen_back = carried & theme_fallbacks.keys
    drawn = builtin_themes.map do |theme|
      still_fallen_back.map { |key| [theme.colors.public_send(key)] }
    end
    expect(drawn.uniq).to eq([still_fallen_back.map { |k| theme_fallbacks[k] }])
  end

  it "carries each key whose fallback was deleted at the colour it drew" do
    drawn = builtin_themes.map do |theme|
      pinned.keys.to_h { |key| [key, theme.colors.public_send(key)] }
    end
    expect(drawn.uniq).to eq([pinned])
  end
end
