# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # The name PlantUML lets an opener carry: `@startuml foo` and
      # `@startuml(id=foo)`. PlantUML uses it only to name the output file; it
      # never changes the drawing, so the parsers accept it and drop it, and
      # the notation hands it to the caller through {Notation::Parsed#name}.
      #
      # The name is the source text as written, stripped. It is untrusted:
      # it may hold spaces, dots, slashes (`../evil`) or quotes. Sirena never
      # uses it as a path; a caller that does must sanitise it first.
      module DiagramName
        extend self

        # `@start<tag>`, then an optional `(id=NAME)` and optional text.
        OPENER = /\A@start[a-z]+(?:\((?:id=)?([^)]*)\))?(?:[ \t]+(.*))?\z/
        PAD = '[ \t\v\f\x00]'
        # The first line that is not blank and not a `'` comment, after an
        # optional byte order mark; matched on raw bytes so no input raises.
        FIRST_LINE = /\A(?:\xEF\xBB\xBF)?
                      (?:#{PAD}*(?:'[^\r\n]*)?(?:\r\n|\r|\n))*
                      #{PAD}*(@start[^\r\n]*)/xn
        private_constant :OPENER, :PAD, :FIRST_LINE

        # @param source [String] PlantUML source, any bytes
        # @return [String, nil] the name the opener carries, or nil when it
        #   carries none, is not valid UTF-8, or the source has no opener
        def read(source)
          line = opener_line(source)
          match = line && OPENER.match(line)
          clean(match && (match[2] || match[1]))
        end

        private

        # nil when there is no opener or its bytes are not valid UTF-8.
        def opener_line(source)
          line = FIRST_LINE.match(source.b)&.[](1)&.force_encoding("UTF-8")
          line.strip if line&.valid_encoding?
        end

        def clean(name)
          name = name&.strip
          name unless name.nil? || name.empty?
        end
      end
    end
  end
end
