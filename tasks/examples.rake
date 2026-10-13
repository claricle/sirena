# frozen_string_literal: true

require_relative "example_tasks"

# The bodies of the examples:* tasks. They live here, as methods, so each
# rake block below is a one-line call and the namespace blocks stay short.
# `__dir__` is this file's directory, exactly as it was inside the tasks.
module ExampleRakeTasks
  EXAMPLES_DIR = File.expand_path("../examples", __dir__)
  DOCS_ASSETS_DIR = File.expand_path("../docs/assets/examples", __dir__)
  DOCS_EXAMPLES_DIR = File.expand_path("../docs/_diagram_types/examples",
                                       __dir__)

  DESCRIPTIONS = {
    generate: "Generate all example SVGs from source files",
    prune: "Delete example SVGs whose source is gone or never renders " \
           "(destructive, deliberate)",
    copy_to_docs: "Copy generated examples to docs/assets/examples",
    generate_docs: "Generate AsciiDoc include files for documentation",
    validate: "Validate all examples (parse and render)",
    list: "List all examples with status",
    init: "Initialize examples directory structure",
    clean: "Clean stale generated directories and documentation copies",
  }.freeze

  README_CONTENT = <<~README
    # Sirena Examples

    This directory contains example diagrams for all supported diagram types.

    ## Structure

    Each diagram type has its own directory with:
    - `*.mmd` - Mermaid source files
    - `*.yml` - Metadata for each example
    - `*.svg` - Rendered output, regenerated in place and committed

    ## Usage

    ```bash
    # Generate all SVGs
    rake examples:generate

    # Create a new example
    rake examples:create[flowchart,my-example]

    # Validate all examples
    rake examples:validate

    # List all examples
    rake examples:list

    # Build everything (generate + docs + copy)
    rake examples:build
    ```

    ## Adding Examples

    1. Create example files:
       ```bash
       rake examples:create[type,name]
       ```

    2. Edit the `.mmd` and `.yml` files

    3. Generate SVG:
       ```bash
       rake examples:generate
       ```

    4. Build documentation:
       ```bash
       rake examples:build
       ```

    ## Example Metadata

    Each `.yml` file should contain:

    ```yaml
    title: "Example Title"
    description: "What this example demonstrates"
    complexity: basic  # basic, intermediate, advanced
    keywords:
      - keyword1
      - keyword2
    use_cases:
      - "Use case description"
    theme: default  # default, dark, light, high-contrast
    ```
  README

  GITIGNORE_CONTENT = <<~GITIGNORE
    # Stale generated/ directories from older checkouts. Nothing writes them
    # now — the generated SVGs sit beside their sources — but leaving the rule
    # keeps an old working copy quiet and stops `git add examples/` sweeping
    # stale output back in.
    */generated/

    # Ignore macOS files
    .DS_Store

    # Ignore editor files
    *.swp
    *.swo
    *~
  GITIGNORE

  module_function

  def generate
    require "sirena"
    require "yaml"
    require "fileutils"
    require_examples_dir!(EXAMPLES_DIR)

    total_generated, failed_renders =
      ExampleTasks.with_examples_lock(EXAMPLES_DIR) do
        ExampleTasks.generate_examples(EXAMPLES_DIR)
      end

    report_failed_renders(failed_renders, EXAMPLES_DIR)
    print_generation_summary(total_generated, failed_renders)
  end

  def require_examples_dir!(examples_dir)
    return if Dir.exist?(examples_dir)

    puts "⚠️  Examples directory not found: #{examples_dir}"
    puts "Run 'rake examples:init' to create the directory structure"
    exit 1
  end

  def report_failed_renders(failed_renders, examples_dir)
    ExampleTasks.handle_failed_svgs(failed_renders, examples_dir)
  rescue ExampleTasks::UnexpectedRenderFailure
    exit 1
  end

  def print_generation_summary(total_generated, failed_renders)
    puts "\n#{'=' * 60}"
    puts "✅ Example generation complete!"
    puts "   Generated: #{total_generated}"
    puts "   Failed: #{failed_renders.size}"
    puts "=" * 60
  end

  def prune
    examples_dir = EXAMPLES_DIR

    ExampleTasks.with_examples_lock(examples_dir) do
      puts "Pruning example SVGs with no source..."
      report_pruned(ExampleTasks.prune_orphan_svgs(examples_dir), "orphaned")

      puts "\nPruning example SVGs beside a source that never renders..."
      report_pruned(ExampleTasks.prune_known_unrenderable_svgs(examples_dir),
                    "stale")
    end
  end

  def report_pruned(removed, adjective)
    message = "Removed #{removed} #{adjective} SVG(s)."
    puts removed.zero? ? "Nothing to prune." : message
  end

  # No pre-creation of docs_assets_dir here: ExampleTasks.copy_to_docs
  # creates it itself, AFTER its own verified_root guard runs, not before.
  # Creating it here first (as this task used to) meant `FileUtils.mkdir_p`
  # would walk through a symlinked ancestor and leave a real, empty
  # directory outside the repo even when the guard went on to abort the
  # task for exactly that ancestor -- reproduced by execution: a symlink at
  # docs/assets left `outside_target/examples` created before the guard
  # ever ran.
  def copy_to_docs
    copied = ExampleTasks.with_examples_lock(EXAMPLES_DIR) do
      ExampleTasks.copy_to_docs(EXAMPLES_DIR, DOCS_ASSETS_DIR)
    end
    print_copied(copied)
  end

  def print_copied(copied)
    copied.each do |diagram_type, count|
      puts "✓ Copied #{count} #{diagram_type} examples to docs/assets/examples/"
    end

    puts "\n✅ #{copied.sum { |_, count| count }} examples copied to " \
         "documentation!"
  end

  def generate_docs
    require "yaml"
    require "fileutils"

    FileUtils.mkdir_p(DOCS_EXAMPLES_DIR)

    example_dirs(EXAMPLES_DIR).each do |dir|
      mmd_files = Dir.glob(File.join(dir, "*.mmd"))
      write_docs_include(dir, mmd_files) unless mmd_files.empty?
    end

    puts "\n✅ Documentation includes generated!"
  end

  # Real diagram directories only, sorted: dot-directories (.git and the
  # like) are not diagram types.
  def example_dirs(examples_dir)
    subdirectories(examples_dir).sort.reject do |dir|
      File.basename(dir).start_with?(".")
    end
  end

  def subdirectories(examples_dir)
    Dir.glob(File.join(examples_dir, "*")).select { |f| File.directory?(f) }
  end

  def write_docs_include(dir, mmd_files)
    diagram_type = File.basename(dir)
    adoc_file = File.join(DOCS_EXAMPLES_DIR, "#{diagram_type}-examples.adoc")

    content = ["// Auto-generated examples for #{diagram_type}",
               "// Generated by rake examples:build", ""]
    mmd_files.each_with_index do |mmd_file, index|
      content.concat(docs_example_lines(dir, mmd_file, index))
    end

    File.write(adoc_file, content.join("\n"))
    puts "✓ Generated #{diagram_type}-examples.adoc " \
         "(#{mmd_files.size} examples)"
  end

  def example_metadata(dir, basename)
    yml_file = File.join(dir, "#{basename}.yml")
    File.exist?(yml_file) ? YAML.load_file(yml_file) : {}
  end

  def docs_example_lines(dir, mmd_file, index)
    basename = File.basename(mmd_file, ".mmd")
    metadata = example_metadata(dir, basename)
    title, description, complexity, use_cases = docs_fields(metadata, basename)

    ["==== Example #{index + 1}: #{title}", "", ".#{description}",
     *docs_note_lines(complexity, use_cases), "",
     ".Source Code", "[source,mermaid]", "----",
     File.read(mmd_file).strip, "----", "",
     ".Rendered Output",
     "image::../../../assets/examples/#{File.basename(dir)}/#{basename}" \
     ".svg[#{title},600]",
     "", "'''", ""]
  end

  def docs_fields(metadata, basename)
    fallback_title = basename.split("-").map(&:capitalize).join(" ")
    [metadata["title"] || fallback_title,
     metadata["description"] || "Example diagram",
     metadata["complexity"] || "basic",
     metadata["use_cases"] || []]
  end

  def docs_note_lines(complexity, use_cases)
    return [] if use_cases.empty? && complexity == "basic"

    lines = ["[NOTE]", "====", "Complexity: #{complexity.capitalize}"]
    lines.push(" +", "Use Cases: #{use_cases.join(', ')}") unless
      use_cases.empty?
    [*lines, "===="]
  end

  def validate
    require "sirena"
    require "yaml"

    begin
      ExampleTasks.validate_examples(EXAMPLES_DIR)
    rescue ExampleTasks::ValidationFailed => e
      warn e.message
      exit 1
    end
  end

  def create(type, name)
    require "fileutils"

    require_type_and_name!(type, name)
    type_dir = File.join(EXAMPLES_DIR, type)
    FileUtils.mkdir_p(type_dir)
    basename = format("%<number>02d-%<name>s",
                      number: next_example_number(type_dir), name: name)
    write_example_template(type_dir, basename, type, name)

    puts "✓ Created #{basename}.mmd"
    puts "✓ Created #{basename}.yml"
    puts "\nEdit these files and run: rake examples:generate"
  end

  def require_type_and_name!(type, name)
    return unless type.nil? || name.nil?

    puts "Usage: rake examples:create[type,name]"
    puts "Example: rake examples:create[flowchart,basic-flow]"
    exit 1
  end

  def next_example_number(type_dir)
    existing = Dir.glob(File.join(type_dir, "*.mmd")).map do |f|
      File.basename(f).split("-").first.to_i
    end.max || 0
    existing + 1
  end

  def write_example_template(type_dir, basename, type, name)
    File.write(File.join(type_dir, "#{basename}.mmd"),
               "#{type}\n  A --> B\n")

    yml_content = <<~YAML
      title: "#{name.split('-').map(&:capitalize).join(' ')}"
      description: "Description of this example"
      complexity: basic
      keywords:
        - #{type}
      use_cases:
        - "Example use case"
      theme: default
    YAML
    File.write(File.join(type_dir, "#{basename}.yml"), yml_content)
  end

  def list
    require "yaml"

    require_listable_dir!(EXAMPLES_DIR)

    diagram_dirs = subdirectories(EXAMPLES_DIR)
    total_examples = diagram_dirs.sort.sum { |dir| list_diagram_type(dir) }

    puts "\n#{'=' * 60}"
    puts "Total: #{total_examples} examples across " \
         "#{diagram_dirs.size} diagram types"
    puts "=" * 60
  end

  def require_listable_dir!(examples_dir)
    return if Dir.exist?(examples_dir)

    puts "Examples directory not found: #{examples_dir}"
    puts "Run 'rake examples:init' to create it"
    exit 1
  end

  # Prints one diagram type and returns how many examples it holds.
  def list_diagram_type(dir)
    return 0 if File.basename(dir).start_with?(".")

    examples = Dir.glob(File.join(dir, "*.mmd"))

    print_type_heading(File.basename(dir), examples.size)
    puts "  (no examples yet)" if examples.empty?
    examples.sort.each { |mmd_file| list_example(dir, mmd_file) }
    examples.size
  end

  def print_type_heading(diagram_type, count)
    puts "\n#{diagram_type.upcase.tr('-', ' ')} (#{count} examples)"
    puts "─" * 60
  end

  def list_example(dir, mmd_file)
    basename = File.basename(mmd_file, ".mmd")
    metadata = example_metadata(dir, basename)
    title = metadata["title"] || basename
    complexity = metadata["complexity"] || "basic"
    svg_exists = File.exist?(File.join(dir, "#{basename}.svg"))

    puts "  #{svg_exists ? '✓' : '✗'} #{basename}: #{title} [#{complexity}]"
  end

  def init
    require "fileutils"

    FileUtils.mkdir_p(EXAMPLES_DIR)
    File.write(File.join(EXAMPLES_DIR, "README.md"), README_CONTENT)
    File.write(File.join(EXAMPLES_DIR, ".gitignore"), GITIGNORE_CONTENT)
    print_init_summary
  end

  def print_init_summary
    puts "✓ Created examples/ directory"
    puts "✓ Created README.md"
    puts "✓ Created .gitignore"
    puts "\n✅ Examples directory initialized!"
    puts "\nNext steps:"
    puts "  1. Create examples: rake examples:create[type,name]"
    puts "  2. Generate SVGs: rake examples:generate"
    puts "  3. Build docs: rake examples:build"
  end

  def remove_directory(dir)
    FileUtils.rm_rf(dir)
    puts "✓ Removed #{dir}"
  end

  def clean
    require "fileutils"

    # Clean the stale generated/ directories older checkouts left behind.
    # The tracked SVGs sit beside their sources now and are not touched.
    Dir.glob(File.join(EXAMPLES_DIR, "*/generated")).each do |dir|
      remove_directory(dir)
    end

    [DOCS_ASSETS_DIR, DOCS_EXAMPLES_DIR].each do |dir|
      remove_directory(dir) if Dir.exist?(dir)
    end

    puts "\n✅ Cleaned stale generated directories and documentation copies!"
  end
end

namespace :examples do
  ExampleRakeTasks::DESCRIPTIONS.each do |name, description|
    desc description
    task(name) { ExampleRakeTasks.public_send(name) }
  end

  desc "Generate all examples and copy to docs"
  task build: %i[generate generate_docs copy_to_docs]

  desc "Create example template for a diagram type"
  task :create, [:type, :name] do |_t, args|
    ExampleRakeTasks.create(args[:type], args[:name])
  end
end
