# frozen_string_literal: true

require "prism"

# Finds clock reads that bypass SpeedClock#wall_time and CpuTiming#cpu_time.
# It parses the source rather than matching text, so a line break, `::` or a
# comment cannot hide a read or invent one. `defined?(Process.times)` does
# not run the call, so it is not a read; `defined?(Process.times.to_a)` runs
# its receiver, so it is; other `defined?` operands are scanned whole. It
# catches a direct call on the constant, bare, `::`-rooted or under Object.
# It does not see dynamic calls (`send`, `public_send`) or a parenthesised
# receiver such as `(Process).times`.
module RawClockReads
  # The method each clock read calls, and the constant it calls it on.
  CALLS = {
    clock_gettime: "Process",
    times: "Process",
    realtime: "Benchmark",
    measure: "Benchmark",
    bm: "Benchmark",
    bmbm: "Benchmark",
    benchmark: "Benchmark",
  }.freeze

  # "path:line" for each raw read in the file.
  def self.find(path)
    lines(File.read(path), path).map { |line| "#{path}:#{line}" }
  end

  # The line of each raw read in the source. Raises if the source does not
  # parse, since the unparsed part could hold a read.
  def self.lines(source, name = "source")
    result = Prism.parse(source)
    unless result.errors.empty?
      message = result.errors.first.message
      raise ArgumentError, "#{name} does not parse: #{message}"
    end

    calls(result.value).map { |call| call.location.start_line }
  end

  def self.calls(node)
    found = children(node).flat_map { |child| calls(child) }
    raw?(node) ? [node, *found] : found
  end

  def self.children(node)
    return node.compact_child_nodes unless node.is_a?(Prism::DefinedNode)

    run_by_defined(node.value)
  end

  # The expressions `defined?(node)` runs. Ruby checks an operand without
  # running it: a call's receiver runs and its arguments are checked in turn,
  # a call with a block runs nothing, and assignments, `&&`, `if` and string
  # interpolation run nothing. Measured by spec/raw_clock_reads_spec.rb.
  def self.run_by_defined(node)
    case node
    when Prism::CallNode then run_by_defined_call(node)
    when Prism::ConstantPathNode then [node.parent].compact
    when Prism::ParenthesesNode then run_by_defined_parentheses(node)
    else run_by_defined_all(checked_parts(node))
    end
  end

  # The operands a container checks one by one.
  def self.checked_parts(node)
    case node
    when Prism::ArrayNode, Prism::HashNode, Prism::KeywordHashNode
      node.elements
    when Prism::AssocNode then [node.key, node.value]
    when Prism::SplatNode then [node.expression]
    when Prism::AssocSplatNode then [node.value]
    else []
    end
  end

  def self.run_by_defined_all(nodes)
    nodes.compact.flat_map { |node| run_by_defined(node) }
  end

  def self.run_by_defined_call(node)
    return [] if node.block

    arguments = node.arguments&.arguments.to_a
    [node.receiver, *run_by_defined_all(arguments)].compact
  end

  def self.run_by_defined_parentheses(node)
    statements = node.body&.body.to_a
    statements.size == 1 ? run_by_defined(statements.first) : []
  end

  def self.raw?(node)
    return false unless node.is_a?(Prism::CallNode)

    owner = CALLS[node.name]
    !owner.nil? && owner == constant_name(node.receiver)
  end

  # The constant a receiver names, or nil. `Process`, `::Process` and
  # `Object::Process` all name "Process"; `Foo::Process` is another class.
  def self.constant_name(node)
    case node
    when Prism::ConstantReadNode then node.name.to_s
    when Prism::ConstantPathNode then path_name(node)
    end
  end

  def self.path_name(node)
    parent = node.parent
    return unless parent.nil? || constant_name(parent) == "Object"

    node.name.to_s
  end

  private_class_method :calls, :children, :run_by_defined, :checked_parts,
                       :run_by_defined_all, :run_by_defined_call,
                       :run_by_defined_parentheses, :raw?, :constant_name,
                       :path_name
end
