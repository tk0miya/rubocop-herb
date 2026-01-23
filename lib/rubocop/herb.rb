# frozen_string_literal: true

# NOTE: require_relative should be sorted in ASCII order
require_relative "herb/characters"
require_relative "herb/configuration"
require_relative "herb/converter"
require_relative "herb/erb_location"
require_relative "herb/erb_parser"
require_relative "herb/extractor"
require_relative "herb/parse_result"
require_relative "herb/patch/team"
require_relative "herb/plugin"
require_relative "herb/processed_source"
require_relative "herb/rubocop_ast_transformer"
require_relative "herb/ruby_renderer"
require_relative "herb/tag"
require_relative "herb/version"

module RuboCop
  module Herb
    # @rbs!
    #   # Union type for all ERB nodes
    #   type erb_node = ::Herb::AST::ERBIfNode
    #                 | ::Herb::AST::ERBUnlessNode
    #                 | ::Herb::AST::ERBElseNode
    #                 | ::Herb::AST::ERBCaseNode
    #                 | ::Herb::AST::ERBWhenNode
    #                 | ::Herb::AST::ERBBeginNode
    #                 | ::Herb::AST::ERBRescueNode
    #                 | ::Herb::AST::ERBEnsureNode
    #                 | ::Herb::AST::ERBBlockNode
    #                 | ::Herb::AST::ERBForNode
    #                 | ::Herb::AST::ERBWhileNode
    #                 | ::Herb::AST::ERBUntilNode
    #                 | ::Herb::AST::ERBContentNode
    #                 | ::Herb::AST::ERBEndNode

    class Error < StandardError; end
  end
end
