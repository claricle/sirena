# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Base do
  let(:diagram) { instance_double(Sirena::Diagram::Base, valid?: true) }
  let(:converted_layout) do
    Class.new(described_class) do
      def scene(_diagram)
        Sirena::Layout::Scene.new(width: theme.typography.font_size_normal,
                                  height: today.year)
      end
    end.new
  end
  let(:engine) { Sirena::Engine.new }
  let(:date_layout_class) do
    Class.new(described_class) do
      def scene(_diagram)
        Sirena::Layout::Scene.new(width: today.year, height: 0)
      end
    end
  end

  describe "#call" do
    it "returns a Scene from a layout" do
      expect(converted_layout.call(diagram, theme: Sirena::Theme::Registry.get(:high_contrast),
                                            today: Date.new(2001, 2, 3)))
        .to have_attributes(width: 16.0, height: 2001)
    end

    it "requires subclasses to build a Scene" do
      expect { described_class.new.call(diagram) }
        .to raise_error(NotImplementedError, /implement #scene/)
    end

    it "treats today: nil as the real date and a pinned date as different" do
      dates = date_layout_class.new

      expect(dates.call(diagram, today: nil).width).to eq(Date.today.year)
      expect(dates.call(diagram, today: Date.new(1999, 1, 1)).width).to eq(1999)
    end

    it "keeps a date pinned with today= when called with today: nil" do
      dates = date_layout_class.new

      dates.today = Date.new(1999, 1, 1)

      expect(dates.call(diagram, today: nil).width).to eq(1999)
    end

    it "does not leak a today: kwarg from one call into the next call " \
       "on the same instance" do
      dates = date_layout_class.new

      dates.call(diagram, today: Date.new(1999, 1, 1))

      expect(dates.call(diagram, today: nil).width).to eq(Date.today.year)
    end

    it "does not clobber a today= pin when a call with today: raises " \
       "on an invalid diagram" do
      dates = date_layout_class.new
      dates.today = Date.new(1999, 1, 1)
      invalid = instance_double(Sirena::Diagram::Base, valid?: false)

      expect { dates.call(invalid, today: Date.new(2020, 5, 5)) }
        .to raise_error(Sirena::Layout::LayoutError)

      expect(dates.call(diagram, today: nil).width).to eq(1999)
    end

    it "treats a #scene supplied by a module mixed into the layout " \
       "as converted" do
      scene_hook = Module.new do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: 3, height: 4)
      end
      mixed_in = Class.new(described_class) { include scene_hook }.new

      expect(mixed_in.call(diagram)).to be_a(Sirena::Layout::Scene)
    end

    it "takes a private scene hook from a layout" do
      hidden = Class.new(described_class) do
        def scene(_diagram) = Sirena::Layout::Scene.new(width: 1, height: 2)
        private :scene
      end.new

      expect(hidden.call(diagram)).to be_a(Sirena::Layout::Scene)
    end

    it "keeps theme a private reader" do
      expect { converted_layout.theme }
        .to raise_error(NoMethodError, /private method/)
    end
  end

  describe "#to_graph" do
    it "aliases #call with the same context keywords" do
      result = converted_layout.to_graph(
        diagram,
        theme: Sirena::Theme::Registry.get(:high_contrast),
        today: Date.new(2001, 2, 3),
      )

      expect(result).to have_attributes(width: 16.0, height: 2001)
    end
  end

  describe "Engine#transform_diagram" do
    it "passes the layout result through and hands the layout " \
       "the theme and date" do
      theme = Sirena::Theme::Registry.get(:high_contrast)
      result = engine.send(:transform_diagram, diagram, converted_layout.class,
                           Date.new(2001, 2, 3), theme)

      expect(result).to have_attributes(width: 16.0, height: 2001)
    end
  end
end
