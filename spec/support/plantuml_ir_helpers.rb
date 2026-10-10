# frozen_string_literal: true

# Helpers for the PlantUML class IR specs.
module PlantUmlIrHelpers
  CORPUS_GLOB = File.expand_path("../plantuml/class/*.puml", __dir__)
  PLAIN = [Symbol, String, Numeric, true, false, nil].freeze

  # A class diagram that uses every construct the IR must carry.
  def feature_source
    <<~PUML
      @startuml
      title Everything
      header Top
      footer Bottom
      caption Cap
      legend Leg
      <style>
      document {
      BackGroundColor #EEEEFF
      title {
      FontSize 20
      FontColor #FF0000
      BackGroundColor #CCCCCC
      }
      }
      </style>
      skinparam classBackgroundColor red
      left to right direction
      +package "Outer" as outer #FFEEAA {
        abstract class Shape<T> <<Entity>> $tag1 {
          {abstract} +area(): double
          #name
          ~run(a, b)
        }
        interface Drawable
      }
      package inner.deep <<Frame>> {
        class Circle {
          +radius : double
          +draw() : void
        }
      }
      class Plain
      Shape <|-- Circle
      Drawable <|.. Circle
      Plain "1" *-- "0..*" Circle : owns >
      Plain o-- Shape
      Plain --> Shape : uses
      Plain ..> Drawable
      Plain -- Circle
      Plain <|--|> Circle
      Plain +-- Shape
      Plain --> Plain : self
      (Plain, Shape) .. Circle
      note right of Plain
        line one

        line three
      end note
      note left of Shape::area #lightblue
        member note
      end note
      @enduml
    PUML
  end

  def parse_class(source)
    Sirena::Notation::PlantUML::Parser.new.parse(source)
  end

  # The corpus sources the parser accepts.
  def corpus_diagrams
    Dir[CORPUS_GLOB].filter_map do |path|
      parse_class(File.read(path))
    rescue Sirena::Notation::PlantUML::UnsupportedConstructError
      nil
    end
  end

  # Every instance variable, recursively, as plain data: what `==` would
  # compare if the notation's value classes defined it.
  def summary(value)
    case value
    when Array then value.map { |item| summary(item) }
    when Hash then value.transform_values { |item| summary(item) }
    when *PLAIN then value
    else instance_summary(value)
    end
  end

  def instance_summary(value)
    value.instance_variables.to_h do |name|
      [name, summary(value.instance_variable_get(name))]
    end
  end
end
