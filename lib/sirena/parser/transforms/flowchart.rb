# frozen_string_literal: true

require 'parslet'
require_relative '../base'
require_relative '../../diagram/flowchart'
require_relative '../metadata_yaml'
require_relative '../mermaid_shapes'
require_relative '../../diagram/containment'

module Sirena
  module Parser
    module Transforms
      # Transform for converting flowchart parse trees to diagram models.
      #
      # Handles transformation of nodes, edges, subgraphs, and styling
      # directives from Parslet parse trees into Flowchart diagram objects.
      class Flowchart < Parslet::Transform
        # Two ways a name can fail, and they are not the same thing.
        # Mermaid does not know `nope`, and says so in words a corpus case
        # quotes. Mermaid does know `bang`, and draws it as a curved
        # outline sirena has no shape for — naming it a rectangle drew a
        # picture the source did not ask for, which is worse than saying no.
        #
        # @raise [Parser::ParseError] on a name sirena will not draw
        def self.metadata_shape(name)
          return nil if name.nil?

          MERMAID_SHAPES.fetch(name) do
            raise Parser::ParseError, unsupported_shape(name)
          end
        end

        def self.unsupported_shape(name)
          return "No such shape: #{name}." unless UNDRAWABLE_SHAPES.include?(name)

          "Shape not supported yet: #{name}."
        end
        private_class_method :unsupported_shape

        # mermaid parses the body with js-yaml: a single-line body as a flow
        # mapping, a multiline one as block YAML. Psych does both, so the
        # rules fall out instead of being reimplemented in the grammar.
        #
        # @raise [Parser::ParseError] on YAML mermaid would also refuse
        def self.metadata_entries(metadata)
          body = line_feeds(metadata_body(metadata))
          body = strip_metadata_comments(body)
          body = break_quoted_newlines(body)
          return {} if body.empty?

          # Mermaid's own wrapping: a single-line body becomes a flow
          # mapping between braces, a multiline one is used as written. It
          # does NOT normalise a missing space after a colon — `shape:rect`
          # is an unknown key there and the node keeps its default, so
          # inserting one made sirena honour something mermaid ignores.
          document = body.include?("\n") ? "#{body}\n" : "{\n#{body}\n}"
          entries(MetadataYaml.value(document))
        end

        # Mermaid turns every carriage return into a line feed before it
        # lexes anything, so a Windows line ending inside the block is an
        # ordinary newline by the time YAML sees it. Reading it as written
        # folded `"one` CR `two"` onto one line, left a `%YAML 1.3` CR
        # unlevelled, and took a body mermaid refuses.
        def self.line_feeds(body)
          body.gsub(/\r\n?/, "\n")
        end

        # Mermaid strips comments before lexing, so metadata never sees them.
        # `%%{` is a directive rather than a comment and stays, and a `%%`
        # with nothing after it is not a comment either.
        #
        # The body is a fragment cut from the middle of a line, so its own
        # first character is not the start of a line — only the newlines
        # inside it start one. Anchoring on `^` instead let the leading
        # whitespace run reach back past `@{` and eat the newline that
        # opened the block, which turned `A@{` nl `%% c` nl `}` into an
        # empty body sirena drew as a rectangle. mmdc refuses it, because
        # what is left after the comment goes is `A@{` nl `}`.
        def self.strip_metadata_comments(body)
          body.gsub(/(?<=\n)#{JS_SPACE}*%%(?!\{)[^\n]+\n?/o, '')
        end

        # A newline inside a double-quoted value is a line break to
        # mermaid, which rewrites it before js-yaml ever sees it. Letting
        # YAML fold it turned `"one` newline `two"` into `one two`, where
        # mmdc renders `one<br/>two`.
        def self.break_quoted_newlines(body)
          body.gsub(/"[^"]*"/) { |run| run.gsub(QUOTED_BREAK, '<br/>') }
        end

        # mermaid's lexer runs `/\n\s*/g` over the text between the quotes,
        # and that `\s` is JavaScript's. Ruby's is the five ASCII ones, so
        # a no-break space after the newline stayed in the label and mmdc
        # dropped it. The set below is JavaScript's exactly: it takes the
        # line and paragraph separators and the byte-order mark, and it
        # leaves the next-line character and the zero-width space alone.
        JS_SPACE = '[\t\n\v\f\r \u00a0\u1680\u2000-\u200a' \
                   '\u2028\u2029\u202f\u205f\u3000\ufeff]'

        QUOTED_BREAK = /\n#{JS_SPACE}*/

        private_constant :JS_SPACE, :QUOTED_BREAK

        # A key sirena does not read is left alone rather than validated:
        # `A@{ extra: true }` is a node mmdc draws, and a merge key is one
        # of those. A root that is not a mapping has neither key, and mmdc
        # draws the node untouched.
        #
        # Mermaid reads eight more keys off the document. Six of them
        # (`labelType`, `form`, `pos`, `w`, `h`, `constraint`) leave the
        # picture alone on their own, so ignoring them matches mmdc. Two do
        # not: `A@{ icon: "fa:bell" }` and `A@{ img: "x.png" }` each draw a
        # node with an empty label there, and a plain rectangle named `A`
        # here. Both are node kinds sirena does not have yet.
        def self.entries(document)
          return {} unless document.is_a?(Hash)

          READ_KEYS.filter_map do |key|
            usable = usable_value(key, document[key])
            [key, usable] if usable
          end.to_h
        end

        READ_KEYS = %w[shape label].freeze

        # An empty repeat captures as [], not as an empty slice.
        def self.metadata_body(metadata)
          return '' unless metadata.is_a?(Hash)

          value = metadata[:body]
          value.is_a?(Array) ? '' : value.to_s
        end

        # Mermaid tests the value for truth before using it, so `null`,
        # `false`, `0` and `""` are all no-ops rather than errors — the
        # node keeps what it had. Reading the raw AST made `shape: null`
        # a lookup for a shape called "null".
        #
        # A sequence renders its first element and nothing else: mmdc draws
        # `label: [one, two]` as `one`, and refuses a shape or a nested
        # sequence, where the value it reaches for is not a scalar.
        def self.usable_value(key, value)
          return nil unless truthy?(value)

          value = value.first if value.is_a?(Array) && key == 'label'
          return value if value.is_a?(String)

          raise Parser::ParseError, "Unusable #{key} in metadata."
        end

        # `null`, `false`, `0` and `""` are all falsy to mermaid, which
        # skips the key rather than failing on it. An empty collection is
        # NOT falsy in JavaScript, and mmdc does refuse `label: []`.
        def self.truthy?(value)
          return false if value.nil? || value == false
          return false if value.is_a?(Float) && value.nan?
          return false if value.is_a?(Numeric) && value.zero?
          return false if value.is_a?(String) && value.empty?

          true
        end

        # Shape delimiter to type mapping
        SHAPE_MAP = {
          '[]' => 'rect',
          '()' => 'rounded',
          '([])' => 'stadium',
          '[[]]' => 'subroutine',
          '[()]' => 'cylindrical',
          '(())' => 'circle',
          '((()))' => 'double_circle',
          '>]' => 'asymmetric',
          '{}' => 'rhombus',
          '{{}}' => 'hexagon',
          '[//]' => 'parallelogram',
          '[\\\\]' => 'parallelogram_alt',
          '[/\\]' => 'trapezoid',
          '[\\/]' => 'trapezoid_alt'
        }.freeze

        # Arrow type mapping
        ARROW_MAP = {
          '-->' => 'arrow',
          '->' => 'arrow',
          '---' => 'line',
          '-.>' => 'dotted_arrow',
          '-.-' => 'dotted_arrow',
          '==>' => 'thick_arrow',
          '==' => 'thick_arrow'
        }.freeze

        # mermaid resolves the alias lexemes to a direction word before
        # anything reads one, so `graph <` lays out exactly like `graph RL`.
        # Measured against mmdc 11.12.0: `<` RL, `>` LR, `^` BT, `v` and
        # `BR` TB. Keeping the raw lexeme sent the three glyphs down the
        # default branch in the graph transform and drew them top-to-bottom.
        DIRECTION_ALIASES = {
          '<' => 'RL',
          '>' => 'LR',
          '^' => 'BT',
          'v' => 'TB',
          'BR' => 'TB'
        }.freeze

        # Direction value
        rule(dir_value: simple(:v)) { v.to_s }

        # Node ID
        rule(node_id: simple(:id)) { id.to_s }

        # Shape with label
        rule(
          shape: {
            open: simple(:o),
            label: simple(:l),
            close: simple(:c)
          }
        ) do
          delims = "#{o}#{c}"
          {
            shape_type: SHAPE_MAP[delims] || 'rect',
            label: l.to_s.strip
          }
        end

        # Handle empty labels
        rule(
          shape: {
            open: simple(:o),
            label: sequence(:_),
            close: simple(:c)
          }
        ) do
          delims = "#{o}#{c}"
          {
            shape_type: SHAPE_MAP[delims] || 'rect',
            label: ''
          }
        end

        # Arrow types
        rule(arrow: { plain: simple(:a) }) { a.to_s }
        rule(arrow: { dotted: simple(:a) }) { a.to_s }
        rule(arrow: { thick: simple(:a) }) { a.to_s }

        # Edge label
        rule(label: simple(:l)) { l.to_s.strip }
        rule(label: sequence(:l)) { l.join.strip }

        # Helper method to create nodes
        def self.create_node(node_data)
          Diagram::FlowchartNode.new.tap do |n|
            n.id = node_data[:node_id]
            n.label = node_data[:label] || node_data[:node_id]
            n.shape = node_data[:shape_type] || 'rect'
            n.classes = node_data[:classes] if node_data[:classes]
          end
        end

        # Helper method to create edges
        def self.create_edge(source_id, target_data, arrow_type, label = nil)
          Diagram::FlowchartEdge.new.tap do |e|
            e.source_id = source_id
            e.target_id = target_data[:node_id]
            e.arrow_type = ARROW_MAP[arrow_type] || 'arrow'
            # Convert Parslet::Slice to string before checking empty
            label_str = label.to_s if label
            e.label = label_str if label_str && !label_str.empty?
          end
        end

        # Process parsed diagram
        def self.apply(tree, diagram = nil)
          diagram ||= Diagram::Flowchart.new

          # Parse tree is an array: [header_element, *statement_elements]
          tree = [tree] unless tree.is_a?(Array)

          # Extract header (first element)
          header = tree.first
          if header && header.is_a?(Hash) && header[:direction]
            dir_value = header[:direction][:dir_value] || header[:direction]
            diagram.direction = canonical_direction(dir_value.to_s) if dir_value
          end

          # Process statements (remaining elements)
          statements = tree[1..-1] || []

          assign_ids(statements)
          process_statements(diagram, statements)
          reject_ownership_cycles
          promote_referenced_subgraphs(diagram)

          diagram
        ensure
          # The memo holds a reference to every subgraph statement, so
          # leaving it behind keeps the whole parse tree alive on a
          # long-lived thread until something else parses.
          release_state
        end

        def self.canonical_direction(value)
          DIRECTION_ALIASES.fetch(value, value)
        end
        private_class_method :canonical_direction

        def self.process_statements(diagram, statements, parents = [])
          statements.each do |stmt|
            next unless stmt.is_a?(Hash)

            if stmt[:node]
              # Node with edges
              process_node_edge_statement(diagram, stmt, parents.last)
            elsif stmt[:node_id]
              # Standalone node
              node_data = { node_id: stmt[:node_id], shape_type: 'rect', label: stmt[:node_id] }
              add_or_update_node(diagram, node_data)
              claim_member(parents.last, stmt[:node_id].to_s)
            elsif stmt[:subgraph_keyword]
              process_subgraph(diagram, stmt, parents)
            elsif stmt[:direction_keyword]
              set_direction(parents.last, stmt[:dir_value])
            elsif stmt[:style_keyword] || stmt[:classdef_keyword] ||
                  stmt[:class_keyword] || stmt[:click_keyword]
              # Styling directives (acknowledge but don't fully implement)
              # These are parsed but not processed into the model
            end
          end
        end

        # A subgraph cannot be its own ancestor. mmdc refuses that with
        # "Setting b as parent of a would create a cycle", and the
        # transform was discarding the ids needed to see it.
        #
        # The id is not always the written one. A subgraph declared with a
        # FREE title gets a generated `subGraph<n>` — so `subgraph s Some
        # Title` containing `s` is fine, and containing `subGraph0` is the
        # cycle. Only a bare or bracket-titled declaration keeps its word.
        def self.process_subgraph(diagram, stmt, parents = [])
          id = subgraph_id(stmt)
          ancestry = parents + [id]
          record_subgraph(diagram, stmt, id, parents.last)
          return unless stmt[:subgraph_statements]

          sub_stmts = stmt[:subgraph_statements]
          sub_stmts = [sub_stmts] unless sub_stmts.is_a?(Array)
          process_statements(diagram, sub_stmts, ancestry)
        end

        # Ids are handed out in one pass before anything reads them.
        # `subgraph_id` is asked for the same statement from several
        # places, and a counter that ticked on every call skipped numbers:
        # a subgraph nested in another came out `subGraph2`.
        #
        # mermaid numbers the innermost box first, so the walk goes down
        # before it hands anything out. Measured on mmdc 11.12.0:
        # `subgraph a One` holding `subgraph b Two` makes b subGraph0 and
        # a subGraph1.
        def self.assign_ids(statements)
          statements = [statements] unless statements.is_a?(Array)

          statements.each do |stmt|
            next unless stmt.is_a?(Hash) && stmt[:subgraph_keyword]

            assign_ids(stmt[:subgraph_statements]) if stmt[:subgraph_statements]
            state[:ids][stmt] = allocate_id(stmt)
          end
        end

        # A quoted id arrives as a Hash, and `to_s` on that gave
        # `{string: "s"}`, so a quoted self-parent slipped through.
        def self.subgraph_id(stmt)
          state[:ids][stmt] ||= allocate_id(stmt)
        end

        def self.allocate_id(stmt)
          generated_id?(stmt) ? next_generated_id : written_id(stmt)
        end

        # A free title always generates one. So does a bare id carrying
        # whitespace — `subgraph "a b"` is subGraph0 titled "a b". A
        # bracket title keeps the written id even then, so
        # `subgraph "a b" [T]` stays `a b`. All measured on mmdc 11.12.0.
        def self.generated_id?(stmt)
          return true if free_titled?(stmt)

          stmt[:subgraph_title].nil? && written_id(stmt).match?(/\s/)
        end

        def self.written_id(stmt)
          plain_id(stmt[:subgraph_id])
        end

        # A quoted id arrives as `{string: <slice>}`, so a bare `to_s`
        # gives `{string: "a"@21}` and never matches the id it names.
        # Every place that compares an id has to unwrap it, not just the
        # subgraph's own — the cycle walk reads node ids too.
        def self.plain_id(raw)
          return raw.to_s unless raw.is_a?(Hash)

          value = raw.values.first
          value.is_a?(Array) ? value.join : value.to_s
        end

        # The grammar captures a bracket title WITHOUT its brackets, so
        # the text cannot tell the two forms apart. They carry different
        # keys for that reason — testing for a leading `[` read every
        # bracketed title as free and generated an id for it.
        def self.free_titled?(stmt)
          !stmt[:subgraph_free_title].nil?
        end

        # A box cannot end up inside itself. An ancestor chain only sees
        # loops that nest, and two declarations can close one between
        # them — `a` holding `b` while `b` holds `a` — so each edge is
        # recorded as its claim is won, and the whole set is checked
        # once the diagram has been read.
        #
        # Read from the ARBITRATED graph, not from what the source
        # writes. A claim that lost makes no edge, because the box it
        # named already belongs to somebody else and mermaid never hangs
        # it there. Measured on mmdc 11.12.0: `subgraph c` holding `b`,
        # then `b` holding `a`, then `a` holding `b` draws clusters `c`
        # and `b` — the last claim loses, so nothing closes. Walking the
        # written source instead refused a diagram mmdc draws.
        def self.reject_ownership_cycles
          loop_found = Diagram::Containment.looping_pair(state[:ownership])
          return if loop_found.nil?

          parent, child = loop_found
          raise Parser::ParseError,
                "Setting #{parent} as parent of #{child} would create " \
                'a cycle.'
        end

        def self.next_generated_id
          state[:counter] += 1
          "subGraph#{state[:counter]}"
        end

        # One parse's bookkeeping, kept off the class. A gem runs inside
        # somebody else's app, and these used to be shared: 11 of 36
        # concurrent parses of a 60-box diagram handed out ids that
        # disagreed with the sequential answer.
        #
        # `Thread#[]` is fiber-local, which is the narrower of the two and
        # still right here: `apply` runs a parse start to finish without
        # yielding, so no parse can straddle two fibers.
        #
        # Ids are keyed by identity, because two subgraphs written the
        # same way are still two boxes and each needs its own.
        def self.state
          Thread.current[:sirena_flowchart_transform] ||= fresh_state
        end

        def self.fresh_state
          { ids: {}.compare_by_identity, ownership: {}, counter: -1,
            boxes: {}, claimed: {} }
        end

        def self.release_state
          Thread.current[:sirena_flowchart_transform] = nil
        end

        # Declaration order is kept for painting. Ownership is independent:
        # a parent declared later can adopt an earlier top-level subgraph.
        #
        # Being written inside a box is a claim like any other, so a
        # declaration takes the id only if nothing named it earlier. When
        # it loses, the box is still built and still holds what it
        # contains — it just does not become anybody's child, and the
        # earlier claimant adopts it once the walk is over.
        def self.record_subgraph(diagram, stmt, id, parent)
          box = Diagram::FlowchartSubgraph.new
          box.id = id
          box.declared_title = subgraph_label(stmt)
          diagram.subgraphs << box
          # First box wins the name, matching how a node is claimed, and
          # every later mention adds to that one.
          holding = (state[:boxes][id] ||= box)

          holder = claim(parent, id)
          return if holder.nil?

          # The box that HOLDS the id, not the one just built. Writing a
          # subgraph twice makes a second object, and the second one is
          # empty — everything inside it is claimed for the first. So
          # parenting the new object left the drawable box orphaned at
          # the top level: `subgraph b` at the top, redeclared inside
          # `a`, drew `a` and `b` side by side where mmdc nests them.
          holding.parent_id = parent
          holder.child_ids << id
        end

        # A bracketed title stands alone. A free one keeps the word that
        # looks like an id, and the gap after it, because mermaid labels
        # `subgraph s Some Title` with the whole run and generates the id
        # separately. Measured against mmdc 11.12.0.
        def self.subgraph_label(stmt)
          return stmt[:subgraph_title].to_s if stmt[:subgraph_title]

          if free_titled?(stmt)
            return [written_id(stmt), stmt[:subgraph_free_gap],
                    stmt[:subgraph_free_title]].join
          end

          # The text that was too spaced to serve as an id becomes the
          # title instead, trimmed: `subgraph " ab"` is titled "ab".
          generated_id?(stmt) ? written_id(stmt).strip : nil
        end

        # The one ownership rule: the first box to name an id keeps it,
        # whether it named a node or another box. Source order decides
        # and nothing else. Measured against mmdc 11.12.0; the shapes
        # are one apiece in flowchart_subgraph_ownership_spec.rb.
        #
        # A declaration at the TOP level claims nothing, which is why
        # `subgraph b / X / end` followed by `subgraph c / b / end` still
        # leaves b inside c.
        #
        # This used to be written twice, once here and once as `adopt`'s
        # "unless the parent is already set". The two disagreed, and a
        # later nested declaration took an id an earlier reference had
        # already claimed.
        #
        # @return [Diagram::FlowchartSubgraph, nil] the box that took it
        def self.claim(parent, id)
          box = enclosing(parent)
          return nil if box.nil? || id.empty? || state[:claimed][id]

          state[:claimed][id] = true
          # The edge the cycle check reads. Only a WINNING claim makes
          # one, which is what stops a losing claim from closing a loop
          # that mermaid never sees. No `include?` guard: an id is
          # claimed once, so it can be listed only once.
          (state[:ownership][box.id] ||= []) << id
          box
        end

        # `<<`, not `+=`. Each instance gets its own array from the
        # attribute default, so appending touches nobody else, and `+=`
        # went through the model's collection setter once per member —
        # 1,600 nodes in one box took 2.3 seconds instead of half a
        # millisecond.
        def self.claim_member(parent, node_id)
          box = claim(parent, node_id)
          box.node_ids << node_id if box
        end

        # Indexed rather than searched. Scanning every box for every node
        # made a 240-subgraph diagram take four times as long to parse as
        # it did before subgraphs were modelled.
        def self.enclosing(parent)
          parent.nil? ? nil : state[:boxes][parent]
        end

        # `direction` inside a box turns that box's contents, and mmdc
        # accepts a top-level one without honouring it — measured on
        # 11.12.0, where `flowchart TD` followed by `direction LR` still
        # stacks its nodes vertically. So there is nothing to do when no
        # box encloses it.
        def self.set_direction(parent, value)
          box = enclosing(parent)
          box.direction = value.to_s if box
        end

        # An id that names a subgraph names the BOX, not a node beside it.
        # `one --> two` joins two clusters, and a bare `b` inside
        # `subgraph a` nests box b in a. Measured on mmdc 11.12.0: every
        # form of the reference — bare, shaped, an edge endpoint, written
        # before or after the declaration — draws no node.
        #
        # Left until the walk is over because an EMPTY box is the
        # exception: mmdc draws `subgraph one` / `end` joined by an edge
        # as a plain node, and nothing knows what a box holds until every
        # statement has been read.
        #
        # The ids are collected first and the nodes swept once. Asking
        # `find_node` per box rescans the whole collection each time, and
        # a chain of 2,000 boxes spent 17 seconds in the transform where
        # this takes under one.
        def self.promote_referenced_subgraphs(diagram)
          holders = holders_by_member(diagram)
          promoted = surviving_boxes
          return if promoted.empty?

          promoted.each_value { |box| adopt(holders[box.id], box) }
          diagram.nodes.reject! { |node| promoted.key?(node.id) }
        end

        # A box is worth drawing when it holds something, and holding
        # something is exactly what the model already calls `drawable?`.
        #
        # This used to settle by fixed point, re-checking whether taking
        # a reference out of a box had left that box empty. Once `claim`
        # became the single ownership rule that stopped being possible:
        # an id sitting in a box's `node_ids` is an id that box WON, so
        # no declaration parented it elsewhere and the box keeps it.
        # `adopt` is the only later writer and it MOVES an id from
        # `node_ids` to `child_ids` on the same holder, so no pass can
        # leave a box holding less than it holds now.
        #
        # Measured before deleting the loop — 2,312 sources, 301 calls to
        # the old predicate, zero that disagreed with `drawable?`.
        def self.surviving_boxes
          state[:boxes].select { |_id, box| box.drawable? }
        end

        def self.holders_by_member(diagram)
          diagram.subgraphs.each_with_object({}) do |box, acc|
            box.node_ids.each { |id| acc[id] = box }
          end
        end

        # The box that claimed the reference becomes the parent, with
        # nobody to argue with. Two guards used to say so defensively;
        # both were unreachable, because `parent_id` has exactly two
        # writers — `record_subgraph`, which only runs on a WINNING
        # claim, and this method, which runs after the walk. Holding
        # `box.id` in `node_ids` means this holder won that claim, so
        # no declaration can have set a parent or listed the child.
        # `promoted` is keyed by id, so no box is adopted twice either.
        #
        # Checked as well as argued, before the guards came out: 2,312
        # sources, 50 adoptions, none with a parent already set and none
        # where the holder already listed the child.
        def self.adopt(holder, box)
          return if holder.nil?

          holder.node_ids.delete(box.id)
          box.parent_id = holder.id
          holder.child_ids << box.id
        end

        def self.process_node_edge_statement(diagram, stmt, parent)
          node_data = extract_node_data(stmt[:node])
          add_or_update_node(diagram, node_data)
          claim_member(parent, node_data[:node_id].to_s)

          # Process edges if present
          edges = stmt[:edges]
          return unless edges

          edges = [edges] unless edges.is_a?(Array)
          source_id = node_data[:node_id]

          edges.each do |edge_data|
            next unless edge_data.is_a?(Hash)

            arrow_type = edge_data[:arrow].to_s
            label = edge_data[:label]
            target_data = edge_data[:target]

            next unless target_data

            # Extract and add target node
            target_node_data = extract_node_data(target_data)
            add_or_update_node(diagram, target_node_data)
            claim_member(parent, target_node_data[:node_id].to_s)

            # Create edge
            edge = create_edge(source_id, target_node_data, arrow_type, label)
            diagram.edges << edge

            # For chaining, next edge source is current target
            source_id = target_node_data[:node_id]
          end
        end

        # A second mention of a node changes only what it actually says.
        # Treating an absent shape as `rect` and an absent label as the id
        # meant `A(keep)` followed by `A@{ shape: rect }` kept the round
        # shape and lost the label — mermaid does the opposite of both.
        def self.add_or_update_node(diagram, node_data)
          return unless node_data

          existing = diagram.find_node(node_data[:node_id])
          return diagram.nodes << create_node(node_data) unless existing

          existing.label = node_data[:label] if node_data[:label]
          existing.shape = node_data[:shape_type] if node_data[:shape_type]
          existing.classes = node_data[:classes] if node_data[:classes]
        end

        # Extract node data from parse tree
        def self.extract_node_data(node_hash)
          return nil unless node_hash

          node_id = node_hash[:node_id].to_s
          shape_type, label = bracket_shape(node_hash[:shape])

          # `@{ shape: ..., label: ... }` wins over the bracket form, which
          # is what mermaid does when a node carries both.
          entries = metadata_entries(node_hash[:metadata])

          {
            node_id: node_id,
            shape_type: metadata_shape(entries['shape']) || shape_type,
            label: entries['label'] || label,
            classes: node_hash[:inline_class]&.to_s
          }
        end

        # nil means the source said nothing, which is not the same as
        # saying `rect` or naming the node after itself. `create_node`
        # supplies the defaults, so only a real mention overwrites.
        def self.bracket_shape(shape_data)
          return [nil, nil] unless shape_data

          delims = "#{shape_data[:open]}#{shape_data[:close]}"
          label = shape_data[:label]
          # `A[ ]` is an EMPTY label, not an absent one: mmdc draws a node
          # with nothing in it, and treating it as absent named the node
          # after itself and kept an older label on a re-mention.
          [SHAPE_MAP[delims] || 'rect', label.nil? ? nil : label.to_s.strip]
        end
      end
    end
  end
end
