# frozen_string_literal: true

require "forwardable"
require "herb"

module RuboCop
  module Herb
    # Data class holding the results of parsing an ERB file.
    # Contains the parsed AST, collected ERB locations, and precomputed data
    # needed for rendering. Logic is minimal - mostly data access and simple queries.
    ParseResult = Data.define(
      :source,           #: Source
      :ast,              #: ::Herb::ParseResult
      :erb_locations,    #: Hash[Integer, ErbLocation]
      :erb_max_columns,  #: Hash[Integer, Integer]
      :tags,             #: Hash[Integer, Tag]
      :disabled_cops     #: Hash[String, Array[Range[Integer]]] -- line ranges where each cop is disabled
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
        erb_locations.keys.any? { _1 >= range.from && _1 < range.to }
      end

      # Get all ERB comment nodes
      def erb_comment_nodes #: Array[::Herb::AST::ERBCommentNode]
        erb_locations.values.select(&:comment?).map(&:node) #: Array[::Herb::AST::ERBCommentNode]
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
