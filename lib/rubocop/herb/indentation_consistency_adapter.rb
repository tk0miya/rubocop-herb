# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Prepended to RuboCop::Cop::Layout::IndentationConsistency to compare the indentation of the statements
    # in the same ERB tag only.
    # The columns of the statements in different ERB tags and of HTML are the layout of HTML (they follow
    # the HTML structure and the width of the tag openings), which is left to herb-format.
    # The statements written in a single ERB tag (e.g. the lines of a multi-line `<% %>` tag) are aligned as Ruby code,
    # so they are checked as in Ruby files. Statements spanning multiple ERB tags (e.g. conditionals written
    # across ERB tags) and HTML are not checked.
    module IndentationConsistencyAdapter
      # @rbs!
      #   def processed_source: () -> ::RuboCop::AST::ProcessedSource?

      private

      # Called for each body with its statements and the column to align them with
      # (the column of the first statement by default)
      # @rbs items: Array[::RuboCop::AST::Node]
      # @rbs base_column: Integer?
      def check_alignment(items, base_column = nil) #: void
        source = processed_source
        return super unless source.is_a?(ProcessedSource)

        first_item = items.first
        return super if first_item.nil? || in_single_tag?(source, owner_of(first_item))

        # The base column (from a bare access modifier or Layout/IndentationWidth) is ignored,
        # as it may be given by a statement in another ERB tag
        groups = items.group_by { source.verbatim_code.code_range_of(_1.source_range) }
        groups.each { |code_range, group| super(group) if code_range }
      end

      # The node owning the body containing the statement (e.g. the class of a class body, or kwbegin)
      # @rbs item: ::RuboCop::AST::Node
      def owner_of(item) #: ::RuboCop::AST::Node?
        body = item.parent
        body&.begin_type? ? body.parent : body
      end

      # Whether the node is written in a single ERB tag, where it is checked as in Ruby files
      # @rbs source: ProcessedSource
      # @rbs node: ::RuboCop::AST::Node?
      def in_single_tag?(source, node) #: bool
        return false unless node

        !source.verbatim_code.code_range_of(node.source_range).nil?
      end
    end
  end
end

RuboCop::Cop::Layout::IndentationConsistency.prepend(RuboCop::Herb::IndentationConsistencyAdapter)
