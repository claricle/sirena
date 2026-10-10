# frozen_string_literal: true

# Lays out a user journey written as [[section, [[task, score, actors]]]].
module JourneySceneBuilder
  module_function

  def scene(sections, title: nil)
    diagram = Sirena::Diagram::UserJourney.new(title: title)
    sections.each { |name, tasks| diagram.sections << section(name, tasks) }
    Sirena::Layout::UserJourney.new.to_graph(diagram)
  end

  # A task before any `section` line has no section name.
  def unsectioned
    node = { id: "t1", metadata: { name: "only", score: 4, actors: [] } }
    Sirena::Layout::UserJourney.from_graph({ children: [node] })
  end

  def section(name, tasks)
    journey_tasks = tasks.map do |task_name, score, actors|
      Sirena::Diagram::JourneyTask.new(
        name: task_name, score: score, actors: actors,
      )
    end
    Sirena::Diagram::JourneySection.new(name: name, tasks: journey_tasks)
  end
end
