# frozen_string_literal: true

require "forwardable"
require "herb"

module RuboCop
  module Herb
    # Data class holding the results of parsing an ERB file.
    # Contains the parsed AST, collected ERB locations, and precomputed data
    # needed for rendering. Logic is minimal - mostly data access and simple queries.
    ParseResult = Data.define(
      :source,          #: Source
      :ast,             #: ::Herb::ParseResult
      :erb_locations,   #: Hash[Integer, ErbLocation]
      :erb_positions,   #: Array[Integer] -- start positions of the ERB locations in ascending order
      :erb_tag_ranges,  #: Array[CharRange] -- character ranges of ERB tags (from "<%" to "%>") sorted by position
      :tags,            #: Hash[Integer, Tag]
      :disabled_cops    #: Hash[String, Array[Range[Integer]]] -- line ranges where each cop is disabled
    )

    # Methods are defined by reopening the class (not in a Data.define block)
    # so that rbs-inline can generate their type signatures.
    class ParseResult
      extend Forwardable

      # An ERB comment tag, or the first line of one continuing to the next line
      ERB_COMMENT_TAG = /<%-?#.*?(?:%>|\z)/ #: Regexp

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

      # Whether anything (ERB tags except comments, HTML or text) follows the ERB tag of the node
      # on the line where the tag ends
      # @rbs node: erb_node
      def followed_by_content?(node) #: bool
        tag_closing = node.tag_closing
        return false unless tag_closing

        # Byte positions avoid converting to character positions, which scans the code from its start
        tag_end = tag_closing.range.to
        line_end = code.byteindex("\n", tag_end) || code.bytesize
        code.byteslice(tag_end...line_end).to_s.gsub(ERB_COMMENT_TAG, "").match?(/\S/)
      end
    end
  end
end
