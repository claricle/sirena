# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::ColorPalette do
  include ThemeFallbacks

  let(:asked_for) { theme_keys_asked }

  # Keys whose last fallback was deleted from lib/: the colour it drew.
  let(:pinned) do
    { architecture_group_border: "#999", architecture_group_label: "#333",
      border: "#d1d5db", field_background: "#efefef",
      field_border: "#000000", field_text: "#000000", node_text: "#FFFFFF",
      quadrant_grid_line: "#c7c7f1", radar_axis_line: "#9ca3af",
      radar_grid_line: "#e5e7eb", requirement_box_border: "#333",
      requirement_detail_text: "#666", requirement_element_border: "#00796b",
      requirement_text: "#000", requirement_unknown_risk_border: "#666",
      title_text: "#000000", card_text: "#1f2937", xy_axis_line: "#000000",
      xy_grid_line: "#e5e7eb" }
  end

  it "defines every colour a renderer asks the theme for" do
    unset = builtin_themes.flat_map do |theme|
      asked_for.reject { |key| theme.colors.public_send(key) }
    end
    expect(unset).to be_empty
  end

  it "has no runtime hardcoded paint fallbacks" do
    expect(theme_fallbacks).to be_empty
  end

  it "carries renderer paint roles at the colours they already drew" do
    drawn = builtin_themes.map do |theme|
      pinned.keys.to_h { |key| [key, theme.colors.public_send(key)] }
    end
    expect(drawn.uniq).to eq([pinned])
  end

  describe "categorical palettes" do
    let(:sizes) do
      {
        flow: 8, git_graph: 10, mindmap: 6, pie: 12, quadrant: 4,
        radar: 10, requirement_risk: 3, timeline_fill: 12,
        timeline_text: 12, timeline_rule: 12, treemap: 4,
        user_journey_actor: 6, user_journey_section: 7, xy: 10
      }
    end
    let(:default_journey_palettes) do
      {
        user_journey_actor: %w[
          #8FBC8F #7CFC00 #00FFFF #20B2AA #B0E0E6 #FFFFE0
        ],
        user_journey_section: %w[
          #191970 #8B008B #4B0082 #2F4F4F #800000 #8B4513 #00008B
        ],
      }
    end
    let(:palettes) do
      builtin_themes.to_h do |theme|
        values = sizes.keys.to_h do |name|
          [name, theme.colors.public_send(:"#{name}_palette")]
        end
        [theme.name.to_sym, values]
      end
    end

    def new_dark_palettes
      {
        mindmap: %w[#3794ff #858585 #4ec9b0 #f48771 #89d185 #9cdcfe],
        treemap: %w[#2d2d30 #3e3e42 #404040 #505050],
        quadrant: %w[#2d2d30 #3e3e42 #404040 #505050],
        requirement_risk: %w[#f48771 #dcdcaa #89d185],
        user_journey_actor: %w[
          #3794ff #858585 #4ec9b0 #f48771 #dcdcaa #89d185
        ],
        user_journey_section: %w[
          #1d4ed8 #6d28d9 #be123c #a16207 #15803d #0f766e #0369a1
        ],
      }
    end

    it "has every palette at its full length in every builtin theme" do
      drawn = builtin_themes.map do |theme|
        colors = theme.colors
        sizes.keys.to_h { |n| [n, colors.public_send("#{n}_palette")&.size] }
      end
      expect(drawn).to all(eq(sizes))
    end

    def shared_builtin_palettes
      shared_names = sizes.keys - [:mindmap]
      palettes.values_at(:default, :light, :high_contrast).map do |set|
        set.slice(*shared_names)
      end
    end

    it "gives dark a distinct value for every palette" do
      expect(sizes.keys).to all(satisfy do |name|
        palettes[:dark][name] != palettes[:default][name]
      end)
    end

    it "pins the new dark palettes" do
      expect(palettes[:dark].slice(*new_dark_palettes.keys))
        .to eq(new_dark_palettes)
    end

    it "retains the default journey palettes" do
      expect(palettes[:default].slice(:user_journey_actor,
                                      :user_journey_section))
        .to eq(default_journey_palettes)
    end

    it "shares all existing palettes except mindmap across the other themes" do
      expect(shared_builtin_palettes.uniq.size).to eq(1)
    end

    it "wraps an index past the end of a palette" do
      colors = builtin_themes.first.colors
      wrapped = sizes.map { |name, size| colors.palette(name, size + 1) }
      expect(wrapped).to eq(sizes.keys.map { |name| colors.palette(name, 1) })
    end

    it "refuses a palette name it does not define" do
      expect { builtin_themes.first.colors.palette(:missing, 0) }
        .to raise_error(KeyError, /unknown palette/)
    end

    it "refuses a theme that lacks the palette" do
      bare = described_class.new
      expect { bare.palette(:flow, 0) }.to raise_error(KeyError, /no flow/)
    end
  end
end
