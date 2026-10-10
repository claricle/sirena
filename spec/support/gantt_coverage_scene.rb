# frozen_string_literal: true

# Lays out Gantt source text for the branch-coverage specs of
# Sirena::Layout::Gantt.
module GanttCoverageScene
  module_function

  HEADER = "gantt\n  dateFormat YYYY-MM-DD\n"
  TODAY = Date.new(2024, 1, 1)

  def scene(body, theme: nil)
    lay_out(parse(body), theme: theme)
  end

  def lay_out(document, theme: nil)
    layout = Sirena::Layout::Gantt.new
    layout.theme = theme if theme
    layout.call(document, today: TODAY)
  end

  # The parser only admits durations like 2d, 1w, 3h and 1M, but the
  # layout also takes the private model and IR directly.
  def scene_with_duration(duration)
    diagram = parse("section A\nT1 :a, 2024-01-01, 2d\n")
    diagram.sections.first.tasks.first.duration = duration
    lay_out(diagram)
  end

  def parse(body)
    Sirena::Parser::Gantt.new.parse("#{HEADER}#{body}")
  end

  def tasks(scene)
    scene.sections.flat_map(&:tasks)
  end

  def spans(scene)
    tasks(scene).map { |task| [task.start_date, task.end_date] }
  end

  def settingless_document(body)
    ir = Sirena::Notation::Mermaid::IRAdapters::Gantt.call(parse(body))
    kept = ir.items.reject { |item| item.role == "schedule_settings" }
    Sirena::IR::Prepositioned.new(
      id: ir.id, label: ir.label, role: ir.role,
      items: kept, connections: ir.connections
    )
  end
end
