# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Layout::Base do
  let(:diagram) { instance_double(Sirena::Diagram::Base, valid?: true) }
  let(:legacy_layout) { SpecSupport::LegacyLayout.new }
  let(:converted_layout) do
    Class.new(described_class) do
      def scene(_diagram)
        Sirena::Layout::Scene.new(width: theme.typography.font_size_normal,
                                  height: today.year)
      end
    end.new
  end
  let(:engine) { Sirena::Engine.new }

  describe '#call' do
    it 'returns a Scene bare from a converted layout' do
      expect(converted_layout.call(diagram, theme: Sirena::Theme::Registry.get(:high_contrast),
                                            today: Date.new(2001, 2, 3)))
        .to have_attributes(width: 16.0, height: 2001)
    end

    it 'wraps the graph of an unconverted layout in Layout::Legacy' do
      result = legacy_layout.call(diagram)

      expect(result).to be_a(Sirena::Layout::Legacy)
        .and have_attributes(payload: hash_including(id: 'root'))
    end

    it 'refuses an invalid diagram on a converted layout' do
      invalid = instance_double(Sirena::Diagram::Base, valid?: false)

      expect { converted_layout.call(invalid) }
        .to raise_error(Sirena::Layout::LayoutError)
    end

    it 'refuses an invalid diagram on an unconverted layout' do
      invalid = instance_double(Sirena::Diagram::Base, valid?: false)

      expect { legacy_layout.call(invalid) }
        .to raise_error(Sirena::Layout::LayoutError)
    end

    it 'treats today: nil as the real date and a pinned date as different' do
      dates = Class.new(described_class) do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: today.year, height: 0)
      end.new

      expect(dates.call(diagram, today: nil).width).to eq(Date.today.year)
      expect(dates.call(diagram, today: Date.new(1999, 1, 1)).width).to eq(1999)
    end

    it 'keeps a date pinned with today= when called with today: nil' do
      dates = Class.new(described_class) do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: today.year, height: 0)
      end.new

      dates.today = Date.new(1999, 1, 1)

      expect(dates.call(diagram, today: nil).width).to eq(1999)
    end

    it 'takes a private scene hook as a converted layout' do
      hidden = Class.new(described_class) do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: 1, height: 2)
        private :scene
      end.new

      expect(hidden.call(diagram)).to be_a(Sirena::Layout::Scene)
    end

    it 'keeps theme a private reader' do
      expect { converted_layout.theme }.to raise_error(NoMethodError)
    end
  end

  describe '#to_graph' do
    it 'unwraps the legacy result' do
      expect(legacy_layout.to_graph(diagram)).to include(id: 'root')
    end
  end

  describe 'Engine#transform_diagram' do
    it 'passes the layout result through and hands the layout the theme and date' do
      theme = Sirena::Theme::Registry.get(:high_contrast)
      result = engine.send(:transform_diagram, diagram, converted_layout.class,
                           Date.new(2001, 2, 3), theme)

      expect(result).to have_attributes(width: 16.0, height: 2001)
    end
  end

  describe 'Engine#layout_graph' do
    it 'runs Grid on a legacy result and hands the renderer the bare graph' do
      allow(Sirena::Layout::Grid).to receive(:apply).and_call_original
      graph = engine.send(:layout_graph, legacy_layout.call(diagram))

      expect(Sirena::Layout::Grid).to have_received(:apply).once

      expect(graph).to be_a(Hash)
      expect(graph[:children].first).to include(x: 50, y: 50)
    end

    it 'leaves a Scene untouched, coordinates included' do
      scene = Class.new(Sirena::Layout::Scene) do
        attribute :children, :hash, collection: true
      end.new(width: 1, height: 2, children: [{ x: 7, y: 9 }])

      allow(Sirena::Layout::Grid).to receive(:apply).and_call_original

      expect(engine.send(:layout_graph, scene)).to be(scene)
      expect(Sirena::Layout::Grid).not_to have_received(:apply)
      expect(scene.children).to eq([{ x: 7, y: 9 }])
    end
  end
end
