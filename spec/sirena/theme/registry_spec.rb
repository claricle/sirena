# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Theme::Registry do
  before do
    # Clear registry before each test
    described_class.clear
  end

  describe '.register' do
    it 'registers a theme' do
      theme = Sirena::Theme.new(name: 'test')
      described_class.register('test', theme)

      expect(described_class.get(:test)).to eq(theme)
    end

    it 'allows symbol and string keys' do
      theme = Sirena::Theme.new(name: 'test')
      described_class.register('test', theme)

      expect(described_class.get(:test)).to eq(theme)
      expect(described_class.get('test')).to eq(theme)
    end
  end

  describe '.get' do
    it 'retrieves registered theme' do
      theme = Sirena::Theme.new(name: 'test')
      described_class.register(:test, theme)

      expect(described_class.get(:test)).to eq(theme)
    end

    it 'returns nil for unregistered theme' do
      expect(described_class.get(:nonexistent)).to be_nil
    end
  end

  describe '.list' do
    it 'lists all registered theme names' do
      theme1 = Sirena::Theme.new(name: 'theme1')
      theme2 = Sirena::Theme.new(name: 'theme2')

      described_class.register(:theme1, theme1)
      described_class.register(:theme2, theme2)

      expect(described_class.list).to include(:theme1, :theme2)
    end

    it 'returns empty array when no themes registered' do
      expect(described_class.list).to eq([])
    end
  end

  describe '.load_builtin_themes' do
    it 'loads built-in themes' do
      described_class.load_builtin_themes

      expect(described_class.list).to include(
        :default, :dark, :light, :high_contrast
      )
    end

    it 'loads default theme correctly' do
      described_class.load_builtin_themes
      theme = described_class.get(:default)

      expect(theme).to be_a(Sirena::Theme)
      expect(theme.name).to eq('default')
      expect(theme.colors.node_fill).to eq('#ffffff')
    end

    it 'loads dark theme correctly' do
      described_class.load_builtin_themes
      theme = described_class.get(:dark)

      expect(theme).to be_a(Sirena::Theme)
      expect(theme.name).to eq('dark')
      expect(theme.colors.node_fill).to eq('#2d2d30')
    end

    it 'loads light theme correctly' do
      described_class.load_builtin_themes
      theme = described_class.get(:light)

      expect(theme).to be_a(Sirena::Theme)
      expect(theme.name).to eq('light')
    end

    it 'loads high_contrast theme correctly' do
      described_class.load_builtin_themes
      theme = described_class.get(:high_contrast)

      expect(theme).to be_a(Sirena::Theme)
      expect(theme.name).to eq('high_contrast')
      expect(theme.colors.node_stroke).to eq('#ffffff')
    end
  end

  describe '.clear' do
    it 'removes all registered themes' do
      theme = Sirena::Theme.new(name: 'test')
      described_class.register(:test, theme)

      described_class.clear

      expect(described_class.list).to be_empty
    end
  end
end