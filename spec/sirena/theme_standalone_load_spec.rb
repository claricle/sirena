# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme do
  %w[color_palette effect_styles shape_styles spacing_config
     typography].each do |name|
    it "refuses to load theme/#{name} without Sirena::Theme defined" do
      hide_const("Sirena::Theme")
      path = File.expand_path("../../lib/sirena/theme/#{name}.rb", __dir__)

      expect { load path }.to raise_error(NameError, /Sirena::Theme/)
    end
  end
end
