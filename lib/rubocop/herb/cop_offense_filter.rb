# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Prepended to RuboCop::Cop::Base to disable the cops reporting the code rendered by the conversion
    # (Configuration::VERBATIM_CODE_COPS) except for the code copied verbatim from ERB tags (see VerbatimCode).
    # An offense outside of such code is handled as an offense at a line disabled by a `rubocop:disable` comment.
    # Unlike CommentConfig, it is not affected by `--ignore-disable-comments`, as the offenses are false positives.
    # Cops inspecting files other than ERB templates are not affected.
    module CopOffenseFilter
      # @rbs!
      #   def processed_source: () -> ::RuboCop::AST::ProcessedSource?
      #   def cop_name: () -> String

      private

      # Keep it private as RuboCop::Cop::Base#enabled_lines? is
      # @rbs range: ::Parser::Source::Range
      def enabled_lines?(range) #: bool
        source = processed_source
        return super unless source.is_a?(ProcessedSource) && Configuration::VERBATIM_CODE_COPS.include?(cop_name)
        return false unless source.verbatim_code.include?(range)

        super
      end
    end
  end
end

RuboCop::Cop::Base.prepend(RuboCop::Herb::CopOffenseFilter)
