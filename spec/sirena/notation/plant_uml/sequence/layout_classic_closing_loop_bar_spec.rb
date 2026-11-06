# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

# Offsets are from the first message line, measured on PlantUML 1.2026.6
# (activate/deactivate probes rendered through the JAR for this change).
RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  def scene_of(body)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(
      "@startuml\n#{body}\n@enduml\n",
    )
    parsed.transform.new.call(parsed.diagram)
  end

  def line_y(arrow)
    arrow.path[/M \S+ (\S+)/, 1].to_f
  end

  def measure(body)
    scene = scene_of(body)
    base = line_y(scene.arrows.first)
    [bars_from(scene, base), scene.arrows.map do |a|
      (line_y(a) - base).round(2)
    end]
  end

  def bars_from(scene, base)
    scene.bars.map { |bar| [(bar.y - base).round(2), bar.height.round(2)] }
  end

  it "drops a loop on the lifeline it closes and ends the bar one below it" do
    bars, loops = measure(
      "a -> b: 1\nactivate b\nb -> b: self\ndeactivate b\nb -> a: end",
    )

    expect([bars, loops]).to eq([[[0.0, 35.31]], [0.0, 34.31, 71.62]])
  end

  it "closes a bar `--` written on the loop the same way" do
    bars, loops = measure("a -> b++: 1\nb -> b: s\nb -> b--: t\na -> b: end")

    expect([bars, loops]).to eq([[[0.0, 77.62]], [0.0, 29.31, 76.62, 113.93]])
  end

  it "ends a bar closed after another lifeline's loop below the loop row" do
    bars, loops = measure(
      "a -> b: 1\nactivate b\na -> a: s\ndeactivate b\na -> b: end",
    )

    expect([bars, loops]).to eq([[[0.0, 35.31]], [0.0, 29.31, 71.62]])
  end

  it "leaves a loop that is not the last before the close where it is" do
    bars, loops = measure(
      "a -> b: 1\nactivate b\nb -> b: self\nb -> a: x\ndeactivate b\n" \
      "a -> b: end",
    )

    expect([bars, loops]).to eq([[[0.0, 71.62]], [0.0, 29.31, 71.62, 100.93]])
  end

  it "ends a bar closed after an ordinary message on that message" do
    bars, = measure(
      "a -> b: 1\nactivate b\nb -> a: ret\ndeactivate b\na -> b: end",
    )

    expect(bars).to eq([[0.0, 29.31]])
  end
end
