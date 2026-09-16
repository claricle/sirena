# frozen_string_literal: true

require 'tmpdir'
require 'rexml/document'

# Interprets mmdc output consistently for every development script that asks
# whether Mermaid accepts a source. Process execution stays with each caller.
module MmdcOracle
  CANARY_SOURCE = "flowchart LR\n  A --> B\n"
  ERROR_ROLE = /\baria-roledescription=(["'])error\1/
  XHTML_STYLE = /<style\b[^>]*\bxmlns=(["'])http:\/\/www\.w3\.org\/1999\/xhtml\1/
  SOURCE_ERROR = /\b(?:parse error|unknowndiagramerror|syntax error)\b/i

  Result = Struct.new(:verdict, :diagnostic)

  module_function

  def verdict(input, &runner)
    Dir.mktmpdir('mmdc-oracle') do |dir|
      probe = run_once(input, File.join(dir, 'probe.svg'), &runner)
      return probe unless probe.verdict == :ambiguous

      canary = run_canary(dir, &runner)
      disambiguate(probe, canary)
    end
  end

  # A syntax failure and the intentional `error` diagram use the same renderer
  # and root role. Measured mmdc output differs at the style element: only the
  # failure page serializes it in the XHTML namespace.
  def error_page?(svg)
    root = svg[/<svg\b[^>]*>/].to_s
    ERROR_ROLE.match?(root) && XHTML_STYLE.match?(svg)
  end

  def run_once(input, output)
    status, diagnostic = yield(input, output)
    Result.new(direct_verdict(status, output), diagnostic.to_s)
  rescue SystemCallError => e
    Result.new(:error, e.message)
  end

  def direct_verdict(status, output)
    return :error if status.nil?

    svg = File.binread(output) if File.file?(output)
    # A successful exit with no valid SVG is still infrastructure failure
    # even when nothing was written at all (svg is nil). Beyond that, this
    # check is not limited to the successful path: `error_page?` is a regex
    # over the markup, not an XML validity check, so a process that dies
    # mid-write can leave a truncated document that still carries the
    # error-role and XHTML-style markers a real rejection page has. Only a
    # well-formed SVG earns the semantic :rejects verdict below — a
    # malformed one, whatever the exit status, is a crash, not mermaid
    # answering "no".
    return :error if !valid_svg?(svg) && (successful?(status) || svg)
    return :rejects if svg && error_page?(svg)
    return :accepts if successful?(status)

    :ambiguous
  end

  def run_canary(dir, &)
    input = File.join(dir, 'canary.mmd')
    File.write(input, CANARY_SOURCE)
    run_once(input, File.join(dir, 'canary.svg'), &)
  end

  def disambiguate(probe, canary)
    return Result.new(:rejects, probe.diagnostic) if source_error?(probe.diagnostic)
    return Result.new(:error, probe.diagnostic) if canary.verdict == :accepts

    messages = [probe.diagnostic, canary.diagnostic].reject(&:empty?).uniq
    messages << 'mmdc also failed its known-valid health check' if messages.empty?
    Result.new(:error, messages.join("\n"))
  end

  def successful?(status)
    status == true || (status.respond_to?(:success?) && status.success?)
  end

  def source_error?(diagnostic)
    SOURCE_ERROR.match?(diagnostic)
  end

  def valid_svg?(svg)
    return false unless svg

    REXML::Document.new(svg).root&.name == 'svg'
  rescue REXML::ParseException
    false
  end
end
