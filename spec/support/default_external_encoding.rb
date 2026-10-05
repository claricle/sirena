# frozen_string_literal: true

# Runs a block as if the process locale were not UTF-8. `File.read` and
# `$stdin.read` tag what they return with `Encoding.default_external`, which
# is the locale's encoding (`LC_ALL=en_US.ISO8859-1`, `ja_JP.eucJP`), and
# transcode it to `Encoding.default_internal` when one is set (`ruby -E`).
module DefaultExternalEncoding
  # @param encoding [Encoding, String] the external encoding; a String
  #   `"EXT:INT"` sets the internal encoding too, as `ruby -EEXT:INT` does
  def with_default_external(encoding)
    external, internal = encoding.to_s.split(":")
    original = [Encoding.default_external, Encoding.default_internal]
    silently do
      Encoding.default_external = external
      Encoding.default_internal = internal
    end
    yield
  ensure
    silently do
      Encoding.default_external, Encoding.default_internal = original
    end
  end

  # Runs a block with `$stdin` reading `text` from a pipe. The pipe's read end
  # takes the default external encoding in force when it is made, so call this
  # inside `with_default_external` to get a locale-tagged `$stdin`.
  def with_stdin(text)
    original = $stdin
    reader, writer = IO.pipe
    writer.binmode.write(text.b)
    writer.close
    $stdin = reader
    yield
  ensure
    $stdin = original
    reader&.close
  end

  # `Encoding.default_external=` warns under `-w`, which the suite runs with.
  def silently
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
