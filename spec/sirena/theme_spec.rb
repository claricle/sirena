# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Theme do
  describe '.load' do
    it 'loads theme from YAML file' do
      theme_path = File.join(__dir__, '..', '..', 'lib', 'sirena',
                              'theme', 'builtin', 'default.yml')
      theme = described_class.load(theme_path)

      expect(theme).to be_a(described_class)
      expect(theme.name).to eq('default')
      expect(theme.description).to include('clean')
    end

    it 'loads colors from YAML' do
      theme_path = File.join(__dir__, '..', '..', 'lib', 'sirena',
                              'theme', 'builtin', 'default.yml')
      theme = described_class.load(theme_path)

      expect(theme.colors).to be_a(Sirena::Theme::ColorPalette)
      expect(theme.colors.node_fill).to eq('#ffffff')
      expect(theme.colors.node_stroke).to eq('#000000')
    end

    it 'loads typography from YAML' do
      theme_path = File.join(__dir__, '..', '..', 'lib', 'sirena',
                              'theme', 'builtin', 'default.yml')
      theme = described_class.load(theme_path)

      expect(theme.typography).to be_a(Sirena::Theme::Typography)
      expect(theme.typography.font_family).to include('Arial')
      expect(theme.typography.font_size_normal).to eq(14.0)
    end

    it 'loads shapes from YAML' do
      theme_path = File.join(__dir__, '..', '..', 'lib', 'sirena',
                              'theme', 'builtin', 'default.yml')
      theme = described_class.load(theme_path)

      expect(theme.shapes).to be_a(Sirena::Theme::ShapeStyles)
      expect(theme.shapes.stroke_width).to eq(2.0)
    end

    it 'loads spacing from YAML' do
      theme_path = File.join(__dir__, '..', '..', 'lib', 'sirena',
                              'theme', 'builtin', 'default.yml')
      theme = described_class.load(theme_path)

      expect(theme.spacing).to be_a(Sirena::Theme::SpacingConfig)
      expect(theme.spacing.node_padding_x).to eq(10.0)
    end

    it 'loads effects from YAML' do
      theme_path = File.join(__dir__, '..', '..', 'lib', 'sirena',
                              'theme', 'builtin', 'default.yml')
      theme = described_class.load(theme_path)

      expect(theme.effects).to be_a(Sirena::Theme::EffectStyles)
      expect(theme.effects.shadow_enabled).to be false
    end
  end

  describe '#merge' do
    let(:base_theme) do
      described_class.new(
        name: 'base',
        colors: Sirena::Theme::ColorPalette.new(
          node_fill: '#ffffff',
          node_stroke: '#000000'
        ),
        typography: Sirena::Theme::Typography.new(
          font_size_normal: 14.0
        )
      )
    end

    let(:override_theme) do
      described_class.new(
        name: 'override',
        colors: Sirena::Theme::ColorPalette.new(
          node_fill: '#ff0000'
        )
      )
    end

    it 'merges theme properties' do
      merged = base_theme.merge(override_theme)

      expect(merged.name).to eq('override')
      expect(merged.colors.node_fill).to eq('#ff0000')
    end

    it 'preserves base values when override is nil' do
      override = described_class.new(name: 'test')
      merged = base_theme.merge(override)

      expect(merged.name).to eq('test')
      expect(merged.colors).to eq(base_theme.colors)
    end
  end
end