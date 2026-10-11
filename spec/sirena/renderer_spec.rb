# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer do
  {
    Sirena::Renderer::Gantt => Sirena::Layout::Gantt::Scene,
    Sirena::Renderer::XyChart => Sirena::Layout::XyChart::Scene,
    Sirena::Renderer::Timeline => Sirena::Layout::Timeline::Scene,
  }.each do |renderer_class, scene_class|
    it "makes #{renderer_class} reject non-#{scene_class} input" do
      message = "expected #{scene_class}, got Hash"

      expect { renderer_class.new.render({}) }
        .to raise_error(Sirena::Renderer::RenderError, message)
    end
  end
end
