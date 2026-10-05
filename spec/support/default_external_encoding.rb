# frozen_string_literal: true

# Runs a block as if the process locale were not UTF-8. `File.read` and
# `$stdin.read` tag what they return with `Encoding.default_external`, which
# is the locale's encoding (`LC_ALL=en_US.ISO8859-1`, `ja_JP.eucJP`).
module DefaultExternalEncoding
  def with_default_external(encoding)
    original = Encoding.default_external
    silently { Encoding.default_external = encoding }
    yield
  ensure
    silently { Encoding.default_external = original }
  end

  # Runs a block with `$stdin` reading `text` from a pipe. The pipe's read end
  # takes the default external encoding in force when it is made, so call this
  # inside `with_default_external` to get a locale-tagged `$stdin`.
  def with_stdin(text)
    original = $stdin
    reader, writer = IO.pipe
    writer.write(text)
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
