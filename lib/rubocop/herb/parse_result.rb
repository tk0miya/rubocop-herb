# frozen_string_literal: true

require "forwardable"
require "herb"

module RuboCop
  module Herb
    # Data class holding the results of parsing an ERB file.
    # Contains the parsed AST, collected ERB locations, and precomputed data
    # needed for rendering. Logic is minimal - mostly data access and simple queries.
    ParseResult = Data.define(
      :source,         #: Source
      :ast,            #: ::Herb::ParseResult
      :erb_locations,  #: Hash[Integer, ErbLocation]
      :erb_positions,  #: Array[Integer] -- start positions of the ERB locations in ascending order
      :tags,           #: Hash[Integer, Tag]
      :disabled_cops   #: Hash[String, Array[Range[Integer]]] -- line ranges where each cop is disabled
    )

    # Methods are defined by reopening the class (not in a Data.define block)
    # so that rbs-inline can generate their type signatures.
    class ParseResult
      extend Forwardable

      # @rbs!
      #   def code: () -> String
      #   def byteslice: (::Herb::Range) -> String
      #   def slice: (CharRange range) -> String

      def_delegators :source, :code, :byteslice, :slice

      # Check if a range contains any ERB nodes
      # @rbs range: CharRange
      def contains_erb?(range) #: bool
        pos = erb_positions.bsearch { _1 >= range.from }
        !pos.nil? && pos < range.to
      end

      # Get all ERB comment nodes
      def erb_comment_nodes #: Array[::Herb::AST::ERBCommentNode]
        erb_locations.values.select(&:comment?).map(&:node) #: Array[::Herb::AST::ERBCommentNode]
      end

      # Whether ERB nodes (except comments) follow the ERB comment on the line where the comment ends
      # @rbs node: ::Herb::AST::ERBCommentNode
      def followed_by_erb?(node) #: bool
        line = node.location.end.line
        comment_end = NodeRange.compute_char_range(node, source).to
        index = erb_positions.bsearch_index { _1 >= comment_end } || erb_positions.size
        while (location = erb_location_at(index)) && location.line == line
          return true unless location.comment?

          index += 1
        end
        false
      end

      # Get the ERB location at the index of erb_positions
      # @rbs index: Integer
      def erb_location_at(index) #: ErbLocation?
        pos = erb_positions[index]
        pos && erb_locations[pos]
      end

      # Character ranges of ERB tags (from "<%" to "%>") sorted by position
      # A node split from an ERB tag (e.g. `<% else; end %>`) or an unclosed ERB tag lacks its tag opening
      # or closing, so its content is used instead
      def erb_tag_ranges #: Array[CharRange]
        ranges = erb_locations.values.map do |loc|
          node = loc.node #: erb_node
          from = (node.tag_opening || node.content).not_nil!.range.from
          to = (node.tag_closing || node.content).not_nil!.range.to
          NodeRange.byte_range_to_char_range(::Herb::Range.new(from, to), source)
        end
        ranges.sort_by(&:from)
      end
    end
  end
end
