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

  it "defines every colour a renderer asks the theme for" do
    unset = builtin_themes.flat_map do |theme|
      asked_for.reject { |key| theme.colors.public_send(key) }
    end
    expect(unset).to be_empty
  end

  it "carries each added key at the colour its fallback already drew" do
    drawn = builtin_themes.map do |theme|
      carried.map { |key| [theme.colors.public_send(key)] }
    end
    expect(drawn.uniq).to eq([carried.map { |key| theme_fallbacks[key] }])
  end
end
