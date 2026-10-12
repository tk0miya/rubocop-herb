# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Utility module for Herb AST nodes of ERB tags
    module ErbNode
      # Tag opening of escaped ERB tags (e.g. `<%%` of `<%% x %>` and `<%%= x %>`)
      ESCAPED_TAG_OPENING = "<%%" #: String

      # Whether the node is an escaped ERB tag (e.g. `<%% x %>`), which outputs the tag as text (`<% x %>`)
      # Herb parses it as an ERB node (e.g. `<%% if x %>` as ERBIfNode) like an ordinary ERB tag
      # @rbs node: ::Herb::AST::Node
      def self.escaped?(node) #: bool
        return false unless node.type.start_with?("AST_ERB_")

        erb = node #: erb_node
        erb.tag_opening&.value&.start_with?(ESCAPED_TAG_OPENING) || false
      end
    end
  end
end
