# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Prepended to RuboCop::Cop::ReparsedEquivalence (rubocop 1.92.0+) to compare the reparsed AST
    # with the AST before the transformation by RuboCopASTTransformer.
    # The cops using it (e.g. Style/RedundantParentheses) apply a correction, parse the corrected source again and
    # compare the result with the original AST. The reparsed AST is not transformed, so it never equals
    # the transformed AST of a template with HTML (`(send nil :div)` vs `(send nil :div__html0)`),
    # which drops the offenses and corrections of such cops.
    module ReparsedEquivalenceAdapter
      # @rbs!
      #   def processed_source: () -> ::RuboCop::AST::ProcessedSource?

      private

      # @rbs original_source: String
      # @rbs original_ast: ::RuboCop::AST::Node
      # @rbs corrected_source: String
      def parses_equivalently?(original_source, original_ast, corrected_source) #: bool
        # original_ast is the root of the transformed AST or a scope node in it (e.g. a method definition)
        source = processed_source
        original_ast = source.untransformed_node(original_ast) || original_ast if source.is_a?(ProcessedSource)

        super
      end
    end
  end
end

if defined?(RuboCop::Cop::ReparsedEquivalence)
  RuboCop::Cop::ReparsedEquivalence.prepend(RuboCop::Herb::ReparsedEquivalenceAdapter)
end
