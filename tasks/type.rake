# frozen_string_literal: true

# `rake 'type:new[kanban]'` scaffolds a diagram type and registers it.
# Quote the task: unquoted brackets die in zsh.
namespace :type do
  desc "Scaffold a diagram type: files, specs and its TYPES row"
  task :new, [:name] do |_task, args|
    require "sirena"
    require_relative "support/type_generator"

    name = args[:name] or abort "usage: rake 'type:new[name]'"
    generator = Sirena::TypeGenerator.new(
      name,
      root: File.expand_path("..", __dir__),
      types: Sirena::Notation::Mermaid::TYPES,
    )
    puts generator.call
  rescue Sirena::TypeGenerator::Error => e
    abort "type:new failed: #{e.message}"
  end
end
