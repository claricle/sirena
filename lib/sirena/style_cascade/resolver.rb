# frozen_string_literal: true

require_relative 'resolved_styles'

module Sirena
  module StyleCascade
    # Compiles the classDef declarations for one entity into a
    # `ResolvedStyles`, reproducing mermaid's own `compileStyles` /
    # `styles2Map` / `ErDB#addClass` machinery in one ordered pipeline
    # instead of a set of ad-hoc lookups discovered one probed input at a
    # time.
    #
    #     classDef declarations (raw string per class name)
    #              │
    #              ▼  #expand_declaration   comma-split + color replay, PER class
    #        expanded chunk lists, one per class
    #              │
    #              ▼  #resolve              [default, *assigned], NOT deduped, in order
    #        one ordered chunk list for this entity
    #              │
    #              ▼  #build_exact_map      unlimited-split-keep-first-two, sequential set
    #        ResolvedStyles (exact-case map)
    #
    # `ResolvedStyles` then owns the two divergent READ strategies
    # (attributed vs. cascade) plus the label-color tap — see that class.
    class Resolver
      # Every entity implicitly carries this class ahead of whatever it
      # was explicitly assigned — verified against mermaid's own db,
      # whose `cssClasses` opens with the literal string "default" for
      # every entity, assigned or not.
      DEFAULT_CLASS = 'default'

      # @param class_defs [Hash{String => String}] declared classDef
      #   styles, raw text per class name (as `Diagram::ErDiagram#class_defs`
      #   stores them — one comma-joined string per name, already merging
      #   repeated `classDef name ...` statements for that name)
      def initialize(class_defs)
        @class_defs = class_defs || {}
      end

      # Resolves the style properties an entity's classes apply, by name
      # and not by position. Classes merge left to right into ONE ordered
      # chunk list — mermaid resolves every class's declarations into a
      # single Map at the very end, so a chunk from an earlier class and a
      # same-exact-case chunk from a later class must update the SAME map
      # slot in the SAME left-to-right pass, not merge per-class then
      # `Hash#merge!`.
      #
      # NOT deduped: `assigned_classes` is applied exactly as given, so a
      # repeated assignment moves that class's declarations to the end and
      # lets it win a later conflict — verified against mermaid: `CAR:::a,b`
      # then `CAR:::a` resolves `fill:red` (the trailing "a"), not
      # `fill:blue`.
      #
      # @param assigned_classes [Array<String>] classes assigned to this
      #   entity, in source order, NOT deduped — do not sort or uniq this
      #   before calling
      # @return [ResolvedStyles]
      def resolve(assigned_classes)
        classes = [DEFAULT_CLASS, *assigned_classes]
        chunks = classes.flat_map { |name| chunks_for(name) }

        ResolvedStyles.new(build_exact_map(chunks))
      end

      private

      def chunks_for(class_name)
        declaration = @class_defs[class_name]
        return [] unless declaration

        expand_declaration(declaration)
      end

      # Splits a `classDef` style run ("fill:#f96,stroke:#333") into its
      # raw comma-separated chunks, then REPLAYS a copy of every chunk
      # whose text contains the lowercase substring "color" — anywhere,
      # key or value — onto the end of the list, with the literal
      # substring "fill" rewritten to "bgFill" in that replayed copy only.
      #
      # Verified against mermaid's own db (`ErDB#addClass`): each style
      # chunk is tested with `/color/.exec(s)` (no `i` flag, so only a
      # literal lowercase "color" substring matches) and, on a match, a
      # COPY with "fill"->"bgFill" applied (`a.replace("fill","bgFill")`,
      # first occurrence only, mirrored here by `String#sub`) is pushed a
      # SECOND time into a separate `textStyles` array appended after this
      # class's own `styles` array when compiling — the ORIGINAL chunk
      # still goes into `styles` unrenamed. A declaration naming
      # `stroke:currentcolor` ends up LAST among same-key `stroke` entries
      # even when a later, unrelated `stroke:red` chunk follows it in
      # source, because "stroke" contains no "fill" substring and the
      # replay keeps its own key.
      #
      # The rename is NOT a no-op to skip: an EARLIER account here argued
      # replaying an unrenamed "fill:X" chunk onto an already-identical
      # "fill" entry changes nothing — true only when no OTHER chunk
      # writes to "fill" in between. It is false the moment a later,
      # legitimate same-key chunk exists: `fill:currentcolor,fill:blue`
      # sets fill=currentcolor, then fill=blue (the real, later
      # declaration) — an UNRENAMED replay of the first chunk would land
      # on "fill" a third time and silently revert the legitimate "blue"
      # back to the stale "currentcolor". The rename is what stops that:
      # the replay lands on "bgFill" instead, a key nothing downstream
      # reads, so it cannot clobber a later "fill" write. Verified against
      # a real `mmdc` render: `classDef a fill:currentcolor,fill:blue` on
      # an attributed entity computes `fill="blue"` in mermaid; matching
      # that is exactly what requires the rename.
      #
      # @param declaration [String] raw style text for one class
      # @return [Array<String>] chunks, with colour-bearing ones repeated
      #   (renamed copy appended, original left untouched)
      def expand_declaration(declaration)
        chunks = declaration.split(',')
        replayed = chunks.select { |chunk| chunk.include?('color') }
          .map { |chunk| chunk.sub('fill', 'bgFill') }

        chunks + replayed
      end

      # Splits every "key:value" chunk the way mermaid's own `styles2Map`
      # does, and assigns left to right into ONE accumulator Hash — a
      # repeated exact key updates its value in place (keeping its first
      # position, same as `Map#set` on an existing key) and a new key is
      # appended. Neither key nor value is case-folded: mermaid stores a
      # style declaration verbatim, case untouched ("FILL:red" stays
      # "FILL:red") — case-insensitive matching is the BROWSER's doing, on
      # the finished CSS text, not mermaid's, so folding here would change
      # results mermaid never produces (see `ResolvedStyles#cascade` for
      # where that case-insensitive resolution actually happens, once, at
      # read time).
      #
      # @param chunks [Array<String>] ordered raw "key:value" chunks
      # @return [Hash{String => String}] the exact-case compiled style map
      def build_exact_map(chunks)
        chunks.each_with_object({}) do |chunk, map|
          key, value = mermaid_split(chunk)
          next unless value

          map[key.strip] = value.strip
        end
      end

      # Splits one "key:value" chunk the way mermaid's own `styles2Map`
      # does: `style.split(":")` with NO limit, destructured to only the
      # first two elements. A third colon-separated segment is silently
      # DROPPED, not folded into the value — `fill:red:blue` resolves to
      # `red`.
      #
      # `-1` is required to match JavaScript's `split`: Ruby's default
      # `split` drops a TRAILING empty field, so `"fill:".split(':')`
      # gives `["fill"]` and a value-clearing declaration reads as "no
      # colon" and is skipped. JavaScript (and this, with `-1`) both give
      # `["fill", ""]` instead, which `build_exact_map` reads back as a
      # present-but-empty value.
      #
      # @param chunk [String] one raw "key:value(:ignored)" chunk
      # @return [Array(String, String), Array(String, nil), Array()]
      #   [key, value] — value is nil when the chunk has no colon, and
      #   both are nil (empty array) for an empty chunk
      def mermaid_split(chunk)
        parts = chunk.split(':', -1)
        [parts[0], parts[1]]
      end
    end
  end
end
