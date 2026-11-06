# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # Chains the states of a container that PlantUML draws on one rank:
        # those joined by a flat (single-dash) transition, in the order the
        # transitions run.
        class Rows
          # @param flat [Array<Array(String, String)>] the flat transitions,
          #   as source and target ids
          def initialize(flat)
            @flat = flat
          end

          # @param ids [Array<String>] the states of one container
          # @return [Array<Array<String>>] every state in exactly one chain
          def chains(ids)
            follower = followers(ids)
            chained = (ids - follower.values).map { |id| chain(id, follower) }
            chained + (ids - chained.flatten).zip
          end

          private

          def followers(ids)
            @flat.each_with_object({}) do |(from, to), found|
              next unless joins?(ids, from, to) && !found.key?(from)

              found[from] = to unless found.value?(to)
            end
          end

          def joins?(ids, from, to)
            from != to && ids.include?(from) && ids.include?(to)
          end

          def chain(id, follower)
            row = [id]
            while (onward = follower[row.last]) && !row.include?(onward)
              row << onward
            end
            row
          end
        end
      end
    end
  end
end
