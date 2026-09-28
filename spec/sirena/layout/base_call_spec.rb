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

    it 'refuses an invalid diagram on either branch before dispatching' do
      # The guard in #call runs once, before the respond_to?(:scene) branch,
      # so it fires identically for both branches -- a property this diff
      # introduces (the branch didn't exist before). Its own PASS/FAIL is
      # unchanged from before this diff, so it cannot go red under a revert
      # of these files alone: keep this: it becomes the only check if a
      # future refactor moves the guard inside #scene or #build_graph
      # instead of leaving it in #call.
      invalid = instance_double(Sirena::Diagram::Base, valid?: false)

      expect { converted_layout.call(invalid) }
        .to raise_error(Sirena::Layout::LayoutError)
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

    it 'does not leak a today: kwarg from one call into the next call on the same instance' do
      dates = Class.new(described_class) do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: today.year, height: 0)
      end.new

      dates.call(diagram, today: Date.new(1999, 1, 1))

      expect(dates.call(diagram, today: nil).width).to eq(Date.today.year)
    end

    it 'does not clobber a today= pin when a call with today: raises on an invalid diagram' do
      dates = Class.new(described_class) do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: today.year, height: 0)
      end.new
      dates.today = Date.new(1999, 1, 1)
      invalid = instance_double(Sirena::Diagram::Base, valid?: false)

      expect { dates.call(invalid, today: Date.new(2020, 5, 5)) }
        .to raise_error(Sirena::Layout::LayoutError)

      expect(dates.call(diagram, today: nil).width).to eq(1999)
    end

    it 'treats a #scene supplied by a module mixed into the layout as converted' do
      scene_hook = Module.new do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: 3, height: 4)
      end
      mixed_in = Class.new(described_class) { include scene_hook }.new

      expect(mixed_in.call(diagram)).to be_a(Sirena::Layout::Scene)
    end

    it 'is not fooled by a private #scene inherited from outside the layout hierarchy' do
      # Simulates a host app or gem monkeypatching Kernel with a method of
      # this exact name -- not a layout-defined #scene. respond_to?(:scene,
      # true) alone would match this too, since it walks the WHOLE
      # ancestry, and misdispatch #build_graph-only layouts to it.
      Kernel.module_eval do
        define_method(:scene) { |*| :kernel_scene }
        private :scene
      end

      begin
        expect(legacy_layout.call(diagram)).to be_a(Sirena::Layout::Legacy)
      ensure
        Kernel.send(:remove_method, :scene)
      end
    end

    it 'takes a private scene hook as a converted layout' do
      hidden = Class.new(described_class) do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: 1, height: 2)
        private :scene
      end.new

      expect(hidden.call(diagram)).to be_a(Sirena::Layout::Scene)
    end

    it 'keeps theme a private reader' do
      expect { converted_layout.theme }
        .to raise_error(NoMethodError, /private method/)
    end
  end

  describe '#to_graph' do
    it 'unwraps the legacy result' do
      allow(legacy_layout).to receive(:call)
        .and_return(Sirena::Layout::Legacy.new({ id: 'root' }))

      expect(legacy_layout.to_graph(diagram)).to eq(id: 'root')
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
      payload = { id: 'root', children: [{ id: 'a', width: 50, height: 30 }] }
      graph = engine.send(:layout_graph, Sirena::Layout::Legacy.new(payload))

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
