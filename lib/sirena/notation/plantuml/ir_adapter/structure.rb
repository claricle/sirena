# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module IRAdapter
        # Encodes packages, classes and their members.
        module Structure
          KIND_ROLES = {
            class: "class", abstract: "abstract_class",
            interface: "interface"
          }.freeze
          private_constant :KIND_ROLES

          module_function

          # A relation may end on a package, so the result names both.
          # @return [Hash{String => IR::Node}] the node by class name or
          #   package id
          def call(diagram, sink)
            packages = package_nodes(diagram.packages, sink)
            classes = diagram.classes.to_h do |klass|
              [klass.name, class_node(klass, sink, packages)]
            end
            packages.merge(classes)
          end

          # A package is written after the package it sits inside, so the
          # parent node exists by the time the child is built.
          def package_nodes(packages, sink)
            packages.each_with_object({}) do |package, nodes|
              nodes[package.id] = package_node(package, sink, nodes)
            end
          end

          def package_node(package, sink, nodes)
            node = sink.node("package", package.title,
                             parent: nodes[package.parent])
            sink.detail(node, "source_id", package.id)
            sink.detail(node, "shape", package.shape)
            sink.detail(node, "icon", ("true" if package.icon))
            sink.detail(node, "color", package.color)
            node
          end

          def class_node(klass, sink, packages)
            container = packages[klass.package]
            node = sink.node(KIND_ROLES.fetch(klass.kind), klass.name,
                             parent: container)
            class_details(klass, node, sink)
            klass.body.each { |member| member_node(member, node, sink) }
            node
          end

          def class_details(klass, node, sink)
            sink.details(node, "stereotype", klass.stereotypes)
            sink.detail(node, "generics", klass.generics)
            sink.details(node, "tag", klass.tags)
          end

          def member_node(member, parent, sink)
            node = sink.node(member.kind.to_s, member.name, parent: parent)
            sink.detail(node, "visibility", member.visibility)
            sink.detail(node, "type", member.type)
            sink.detail(node, "parameters", member.parameters)
            sink.details(node, "modifier", member.modifiers)
          end
        end
      end
    end
  end
end
