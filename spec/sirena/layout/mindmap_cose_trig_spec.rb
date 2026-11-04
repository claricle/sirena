# frozen_string_literal: true

require "spec_helper"
require "sirena/js_math"

# Angles in the four quadrants for which the system libm on macOS is one
# bit off the value mmdc's Chrome 131 returns; the expected pair is what
# Chrome's Math.sin and Math.cos print for the same argument.
# The path stays because the coverage guard refuses spec deletions; the
# subject moved to Sirena::JsMath (see spec/sirena/js_math_spec.rb).
RSpec.describe "mindmap COSE trig via JsMath", type: :task do
  [
    [0.4537856055185257, 0.4383711467890774, 0.898794046299167],
    [2.0420352248333655, 0.8910065241883679, -0.4539904997395467],
    [3.2637657012293966, -0.12186934340514774, -0.992546151641322],
    [5.1487212933832724, -0.9063077870366499, 0.4226182617406996],
  ].each do |angle, sine, cosine|
    it "returns the browser's sine and cosine for #{angle}" do
      expect([Sirena::JsMath.sin(angle), Sirena::JsMath.cos(angle)])
        .to eq([sine, cosine])
    end
  end

  it "returns the exact values at zero" do
    expect([Sirena::JsMath.sin(0.0), Sirena::JsMath.cos(0.0)])
      .to eq([0.0, 1.0])
  end

  it "rounds the tiny remainder at pi and half pi correctly" do
    expect([Sirena::JsMath.sin(Math::PI), Sirena::JsMath.cos(Math::PI / 2)])
      .to eq([1.2246467991473532e-16, 6.123233995736766e-17])
  end

  it "is odd in sine and even in cosine" do
    angle = 1.2345
    expect([Sirena::JsMath.sin(-angle), Sirena::JsMath.cos(-angle)])
      .to eq([-Sirena::JsMath.sin(angle), Sirena::JsMath.cos(angle)])
  end
end
