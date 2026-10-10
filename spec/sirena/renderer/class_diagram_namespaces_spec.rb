# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/class_note_svg"

RSpec.describe Sirena::Renderer::ClassDiagram do
  let(:source) do
    "classDiagram\nnamespace Shapes {\n  class Tri\n  class Rect\n}\n" \
      "namespace Other {\n  class Far\n}\nclass Loose\n" \
      "Shapes.Tri --> Other.Far\n"
  end

  let(:box) { ClassNoteSvg.rect(source, "namespace-Shapes") }

  it "draws the namespace title" do
    expect(ClassNoteSvg.texts(source)).to include("Shapes")
  end

  it "shows a namespaced class by its own name" do
    expect(ClassNoteSvg.texts(source)).to include("Tri", "Rect", "Far")
  end

  it "no longer shows the qualified class name" do
    expect(ClassNoteSvg.texts(source)).not_to include("Shapes.Tri")
  end

  it "draws one box per namespace" do
    expect(ClassNoteSvg.group_ids(source).grep(/\Anamespace-/))
      .to eq(%w[namespace-Shapes namespace-Other])
  end

  it "encloses a class in its namespace box" do
    inner = ClassNoteSvg.rect(source, "class-Shapes.Rect")
    expect(ClassNoteSvg.contained?(inner, box)).to be(true)
  end

  it "leaves a class of another namespace outside the box" do
    inner = ClassNoteSvg.rect(source, "class-Other.Far")
    expect(ClassNoteSvg.contained?(inner, box)).to be(false)
  end

  it "leaves a class outside any namespace outside the box" do
    inner = ClassNoteSvg.rect(source, "class-Loose")
    expect(ClassNoteSvg.contained?(inner, box)).to be(false)
  end

  it "still joins classes of different namespaces" do
    expect(ClassNoteSvg.group_ids(source))
      .to include("rel-Shapes.Tri_to_Other.Far")
  end

  it "draws no namespace box when the source has none" do
    expect(ClassNoteSvg.group_ids("classDiagram\nclass A\n").grep(/namespace/))
      .to be_empty
  end
end
