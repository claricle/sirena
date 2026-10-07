# frozen_string_literal: true

require "prism"

# Finds clock reads that bypass SpeedClock#wall_time and CpuTiming#cpu_time.
# It parses the source rather than matching text, so a line break, `::` or a
# comment cannot hide a read or invent one. It catches a direct call on the
# constant, bare, `::`-rooted or under Object. It does not see dynamic calls
# (`send`, `public_send`) or a parenthesised receiver such as `(Process).times`.
# Every call counts, including one under `defined?`, which Ruby does not run:
# a spec that checks the method exists uses `Process.respond_to?(:times)`.
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
    found = node.compact_child_nodes.flat_map { |child| calls(child) }
    raw?(node) ? [node, *found] : found
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

  private_class_method :calls, :raw?, :constant_name, :path_name
end
