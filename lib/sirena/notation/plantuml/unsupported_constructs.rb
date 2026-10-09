# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Names the PlantUML construct on a line the parser does not read.
      #
      # A name is for the person reading the error, not a promise that the
      # construct is valid PlantUML. `name_for` is asked only after the parser
      # has refused a line. `member_construct` is also asked first, because a
      # separator or modifier would otherwise read as a field.
      module UnsupportedConstructs
        extend self

        # The element types of `plantuml -language` (section `;type`, 1.2026.6),
        # less the three the parser reads, plus the statements that are not an
        # element: note, layout, styling and page commands.
        KEYWORDS = %w[
          action actor agent analog annotation archimate artifact binary
          boundary card circle cloud clock collections component concise
          control database dataclass diamond entity enum exception file folder
          frame hexagon json label map metaclass network node nwdiag object
          package packetdiag participant person port portin portout process
          protocol queue record rectangle relationship robust stack state
          storage struct usecase yaml
          allow_mixing allowmixing caption footer header hide hnote legend
          namespace newpage note remove restore rnote scale set show skinparam
          stereotype title together
        ].freeze

        # A keyword that PlantUML reads in any letter case is also a plausible
        # class name (`State --> Idle`), so a keyword whose next token is an
        # arrow is a relation, not that construct.
        KEYWORD = /\A(#{KEYWORDS.join('|')})\b
                   (?![ \t]+(?:"[^"]*"[ \t]+)?\S*(?:--|\.\.|->|<-))/iox

        # Valid in any scope, so a class body names them too.
        GLOBAL_RULES = [
          [/\A!/, "preprocessor directive"],
        ].freeze

        # Tried in order. A String is the construct's name; nil means the
        # first capture group is, lowercased. PlantUML reads keywords and
        # modifiers in any letter case, so a pattern holding letters is /i.
        STATEMENT_RULES = [
          [KEYWORD, nil],
          *GLOBAL_RULES,
          [/\A[+\-#~]package\b/i, "package"],
          [/\A(?:left to right|top to bottom) direction\z/i,
           "layout direction"],
          [/\A(?:abstract|class|interface|static[ \t]+class)\b(?=.*<<)/i,
           "stereotype"],
          [/\A(?:abstract|class|interface|static[ \t]+class)\b/i,
           "class declaration form"],
          [/\.\.>|<\.\./, "dependency arrow"],
          [/[ \t](?:-{3,}|\.{3,}|-[a-z]+-)>?[ \t]/i,
           "arrow direction or length"],
          [/[ \t](?:->|<-|->>|<<-)[ \t]/, "single-dash arrow"],
        ].freeze

        MEMBER_RULES = [
          *GLOBAL_RULES,
          [/\{(?:static|abstract|classifier|field|method)\}/i,
           "member modifier"],
          [/\A(?:--|==|\.\.|__)/, "member separator"],
          [/<</, "stereotype"],
        ].freeze

        private_constant :KEYWORDS, :KEYWORD, :GLOBAL_RULES, :STATEMENT_RULES,
                         :MEMBER_RULES

        # @param text [String] one stripped source line
        # @param scope [Symbol] :statement, or :member inside a class body
        # @return [String] the construct's name
        def name_for(text, scope)
          if scope == :member
            member_construct(text) || "member declaration"
          else
            first_match(STATEMENT_RULES, text) || "statement"
          end
        end

        # @return [String, nil] the name of the unsupported member construct
        #   the line holds, nil when it holds none
        def member_construct(text)
          first_match(MEMBER_RULES, text)
        end

        private

        def first_match(rules, text)
          rules.each do |pattern, name|
            match = pattern.match(text)
            return name || match[1].downcase if match
          end
          nil
        end
      end
    end
  end
end
