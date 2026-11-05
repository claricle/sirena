# frozen_string_literal: true

require_relative "../state/reader"
require_relative "../unsupported_construct_error"
require_relative "../../../error/parse_error"
require_relative "model"

module Sirena
  module Notation
    module PlantUML
      module Network
        # Reads an `nwdiag { ... }` block: networks, the nodes each holds with
        # their attributes, and groups. A node's shape is the first one given
        # for it. A line outside this subset raises
        # {UnsupportedConstructError}.
        class Reader
          NAME = /[A-Za-z_][\w.-]*/
          RULES = [
            [/\Anwdiag\s*\{\z/, :open_diagram],
            [/\Anetwork\s+(#{NAME})\s*\{\z/o, :open_network],
            [/\Agroup\s*(#{NAME})?\s*\{\z/o, :open_group],
            [/\A\}\z/, :close],
            [/\A(address|color|description)\s*=\s*(.+?);?\z/, :setting],
            [/\A(#{NAME})\s*(?:\[(.*)\])?\s*;?\z/o, :node],
          ].freeze
          ATTRIBUTE = /(\w+)\s*=\s*("[^"]*"|[^,\]]+)/
          private_constant :NAME, :RULES, :ATTRIBUTE

          # @param source [String] PlantUML source
          # @return [Diagram]
          # @raise [UnsupportedConstructError] on a line outside the subset
          # @raise [Sirena::Parser::ParseError] when a `{` is never closed
          def parse(source)
            @diagram = Diagram.new(networks: [], shapes: {})
            @scopes = []
            State::Reader.lines_of(source).each { |line| read(*line) }
            raise unclosed unless @scopes.empty?

            @diagram
          end

          private

          def read(text, number)
            text = text.sub(%r{\s*//.*\z}, "")
            return if text.empty?

            RULES.each do |pattern, handler|
              match = pattern.match(text)
              return send(handler, *match.captures) if match
            end
            raise unsupported(text, number)
          end

          def open_diagram
            @scopes.push(@diagram)
          end

          def open_network(name)
            network = Network.new(name: name, nodes: [], groups: [])
            @diagram.networks << network
            @scopes.push(network)
          end

          def open_group(name)
            group = Group.new(name: name, names: [])
            network.groups << group
            @scopes.push(group)
          end

          def close
            @scopes.pop
          end

          def network
            @scopes.reverse.find { |scope| scope.is_a?(Network) } ||
              raise(unsupported("group outside a network", 0))
          end

          def setting(key, value)
            scope = @scopes.last
            return unless scope.respond_to?(:"#{key}=")

            scope.public_send(:"#{key}=", unquote(value))
          end

          def node(name, attributes)
            return unless @scopes.last.is_a?(Network) ||
              @scopes.last.is_a?(Group)

            fields = attributes ? attribute_hash(attributes) : {}
            @diagram.shapes[name] ||= fields["shape"] || "box"
            join(name, fields["address"])
          end

          def join(name, address)
            group = @scopes.last
            group.names << name if group.is_a?(Group)
            return if network.nodes.any? { |m| m.name == name }

            network.nodes << Member.new(name: name, address: address)
          end

          def attribute_hash(text)
            text.scan(ATTRIBUTE).to_h do |key, value|
              [key, unquote(value.strip)]
            end
          end

          def unquote(value)
            value.strip.delete_prefix('"').delete_suffix('"')
          end

          def unsupported(text, number)
            UnsupportedConstructError.new(construct: "nwdiag statement",
                                          line: number, text: text)
          end

          def unclosed
            Sirena::Parser::ParseError.new("nwdiag block is never closed")
          end
        end
      end
    end
  end
end
