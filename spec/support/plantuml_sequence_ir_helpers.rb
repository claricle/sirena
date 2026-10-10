# frozen_string_literal: true

# Helpers for the PlantUML sequence IR specs.
module PlantUmlSequenceIrHelpers
  CORPUS_GLOB = File.expand_path("../plantuml/sequence/*.puml", __dir__)

  # A sequence diagram that uses every construct the IR must carry.
  def sequence_feature_source
    <<~'PUML'
      @startuml
      !pragma teoz true
      hide footbox
      <style>
      sequenceDiagram {
        participant { MinimumWidth 90 HorizontalAlignment left FontColor #112233 FontSize 14 FontStyle italic FontName Arial FontWeight bold LineColor #445566 }
        groupHeader { FontColor #FFFFFF BackGroundColor #333333 FontSize 12 }
      }
      </style>
      box "Front"
      participant Alice as A <<web>> #FF0000
      actor Bob
      end box
      participant "Long Name" as L #transparent
      boundary B1
      control C1
      entity E1
      database D1
      collections Co
      queue Q1
      note left of A : warn
      A -> Bob : plain
      note left : attached left
      Bob --> A : dashed
      A ->> Bob : thin
      A -\ Bob : upper
      A -/ Bob : lower
      A ->x Bob : cross
      A ->o Bob : circle
      A o->o Bob : both circles
      A <- Bob : leftward
      A -[#22A722]> Bob : coloured
      A -[hidden]> Bob : hidden
      [-> A : from left
      A ->] : to right
      ?-> A : local in
      A ->? : local out
      A -> A : self
      A <- A : self left
      A -> Bob ++ : activates
      Bob -> A -- : back
      A -> Bob !! : destroys
      activate A #AABBCC
      deactivate A
      destroy Bob
      note right of A #LightBlue : right
      note over A, Bob : over
      hnote over L : hex
      rnote across : across
      note over A : multi\nline
      == divider ==
      alt first
       A -> Bob : x
      else second
       Bob -> A : y
      end
      loop 3
       opt maybe
        par one
         A -> Bob : p1
        else two
         A -> Bob : p2
        end
       end
      end
      critical c
      break b
      group g [lbl]
      end
      end
      end
      ref over A, Bob : see other
      A -> Bob : par1
      & Bob -> A : par2
      & note over A : par note
      autonumber
      A -> Bob : n1
      autonumber 5
      Bob -> A : n2
      newpage
      A -> Bob : second page
      @enduml
    PUML
  end

  def parse_sequence(source)
    Sirena::Notation::PlantUML::Sequence::Parser.new.parse(source)
  end

  def sequence_corpus_diagrams
    Dir[CORPUS_GLOB].sort.filter_map do |path|
      parse_sequence(File.read(path))
    rescue Sirena::Parser::ParseError,
           Sirena::Notation::PlantUML::UnsupportedConstructError
      nil
    end
  end

  # Every field of a private diagram value, class and all, so two diagrams
  # compare equal only when each nested value does. An Appearance is read
  # through its readers: its settings hash also records which defaults the
  # parser spelled out, which nothing observes.
  def sequence_shape(value)
    case value
    when Sirena::Notation::PlantUML::Sequence::Appearance
      appearance_shape(value)
    when Array then value.map { |item| sequence_shape(item) }
    when Hash then value.transform_values { |item| sequence_shape(item) }
    when Symbol, String, Numeric, nil, true, false then value
    else
      fields = value.instance_variables.to_h do |name|
        [name, sequence_shape(value.instance_variable_get(name))]
      end
      [value.class, fields]
    end
  end

  def appearance_shape(appearance)
    head = appearance.head_style
    readers = %i[min_width alignment tab_fill tab_colour tab_size max_message]
    [*readers.map { |name| appearance.public_send(name) },
     sequence_shape(head)]
  end
end
