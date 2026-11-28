# frozen_string_literal: true

require "parser"

module RuboCop
  module Herb
    # Rebuilds the result of parsing the expanded code (AST, comments, tokens and diagnostics) on the buffer of
    # the Ruby code keeping the positions of the source, converting the positions with ExpandedCode.
    # The buffer does not have the markers of HTML, so the result is not the one of parsing the buffer:
    # it has the nodes and the tokens of the markers at the HTML.
    # The semicolons of the markers have no character in the source, so their tokens are dropped.
    class LocationRemapper
      attr_reader :buffer #: ::Parser::Source::Buffer
      attr_reader :expanded_code #: ExpandedCode

      # @rbs buffer: ::Parser::Source::Buffer -- the buffer of the Ruby code keeping the positions of the source
      # @rbs expanded_code: ExpandedCode
      def initialize(buffer, expanded_code) #: void
        @buffer = buffer
        @expanded_code = expanded_code
      end

      # @rbs node: ::Parser::AST::Node
      def remap_node(node) #: ::Parser::AST::Node
        children = node.children.map { _1.is_a?(::Parser::AST::Node) ? remap_node(_1) : _1 }
        node.updated(nil, children, location: remap_map(node.location))
      end

      # @rbs comments: Array[::Parser::Source::Comment]
      def remap_comments(comments) #: Array[::Parser::Source::Comment]
        comment_class = ::Parser::Source::Comment #: untyped
        comments.map { comment_class.new(remap_range(_1.location.expression)) }
      end

      # @rbs tokens: Array[untyped] -- the tokens of the parser: [type, [value, range]]
      def remap_tokens(tokens) #: Array[untyped]
        tokens.filter_map do |type, (value, range)|
          next if type == :tSEMI && expanded_code.marker_semicolon?(range.begin_pos)

          [type, [value, remap_range(range)]]
        end
      end

      # The diagnostic is copied instead of being built again, as the parsers have their own diagnostics
      # (e.g. the one of Prism keeps its message, which is not built from the reason and the arguments)
      # @rbs diagnostic: ::Parser::Diagnostic
      def remap_diagnostic(diagnostic) #: ::Parser::Diagnostic
        remapped = diagnostic.dup
        remapped.instance_variable_set(:@location, remap_range(diagnostic.location))
        remapped.instance_variable_set(:@highlights, diagnostic.highlights.map { remap_range(_1) })
        remapped.freeze
      end

      private

      # The maps keep their ranges in instance variables (e.g. @expression, @keyword and @heredoc_body),
      # which differ by the type of the node, so all of them are converted
      # @rbs map: ::Parser::Source::Map?
      def remap_map(map) #: ::Parser::Source::Map?
        return nil unless map

        remapped = map.dup
        map.instance_variables.each do |name|
          value = map.instance_variable_get(name)
          remapped.instance_variable_set(name, remap_range(value)) if value.is_a?(::Parser::Source::Range)
        end
        remapped
      end

      # @rbs range: ::Parser::Source::Range
      def remap_range(range) #: ::Parser::Source::Range
        ::Parser::Source::Range.new(
          buffer, expanded_code.to_source_pos(range.begin_pos), expanded_code.to_source_pos(range.end_pos)
        )
      end
    end
  end
end
