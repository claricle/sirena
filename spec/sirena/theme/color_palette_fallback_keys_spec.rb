# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::ColorPalette do
  include ThemeFallbacks

  # One key, several fallback colours in other renderers: each needs its own
  # role first. Kanban and the XY chart already use card_text, xy_axis_line
  # and xy_grid_line instead.
  let(:awaiting_roles) { %i[axis_line border_color grid_line text text_color] }
  let(:asked_for) { theme_keys_asked - awaiting_roles }

  let(:carried) do
    %i[border edge_color field_background field_border field_text
       group_background highlight node_bg node_text note_fill section_bg
       title_text]
  end

  # Keys whose last fallback was deleted from lib/: the colour it drew.
  let(:pinned) do
    { border: "#d1d5db", field_background: "#efefef",
      field_border: "#000000", field_text: "#000000", node_text: "#FFFFFF",
      title_text: "#000000", card_text: "#1f2937", xy_axis_line: "#000000",
      xy_grid_line: "#e5e7eb" }
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

  describe "categorical palettes" do
    let(:sizes) do
      { flow: 8, pie: 12, radar: 10, xy: 10, timeline_fill: 12,
        timeline_text: 12, timeline_rule: 12 }
    end

    it "has every palette at its full length in every builtin theme" do
      drawn = builtin_themes.map do |theme|
        colors = theme.colors
        sizes.keys.to_h { |n| [n, colors.public_send("#{n}_palette")&.size] }
      end
      expect(drawn).to all(eq(sizes))
    end

    it "gives every theme the same palette colours" do
      drawn = builtin_themes.map do |theme|
        sizes.keys.map { |name| theme.colors.public_send(:"#{name}_palette") }
      end
      expect(drawn.uniq.size).to eq(1)
    end

    it "wraps an index past the end of a palette" do
      colors = builtin_themes.first.colors
      wrapped = sizes.map { |name, size| colors.palette(name, size + 1) }
      expect(wrapped).to eq(sizes.keys.map { |name| colors.palette(name, 1) })
    end

    it "refuses a palette name it does not define" do
      expect { builtin_themes.first.colors.palette(:git_graph, 0) }
        .to raise_error(KeyError, /unknown palette/)
    end

    it "refuses a theme that lacks the palette" do
      bare = described_class.new
      expect { bare.palette(:flow, 0) }.to raise_error(KeyError, /no flow/)
    end
  end
end
