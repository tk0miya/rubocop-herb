# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Prepended to RuboCop::Cop::Base to discard autocorrections that would break ERB templates.
    # An autocorrection reaching the delimiters of an ERB tag is trimmed by CorrectionAdjuster
    # (e.g. removing an expression without the delimiters of its ERB tag) before validation.
    # A discarded offense is reported as not autocorrectable.
    # Cops inspecting files other than ERB templates, and the cops of rubocop-herb, are not affected.
    module CopCorrectionGuard
      # @rbs!
      #   def processed_source: () -> ::RuboCop::AST::ProcessedSource?
      #   def cop_name: () -> String

      # `--disable-uncorrectable` inserts `# rubocop:todo` comments, which break ERB templates
      def disable_uncorrectable? #: bool
        return false if processed_source.is_a?(ProcessedSource)

        super
      end

      private

      # Keep it private as RuboCop::Cop::Base#correct is
      # @rbs range: ::Parser::Source::Range
      # @rbs &block: ? (::RuboCop::Cop::Corrector) -> void
      def correct(range, &block) #: [Symbol, ::RuboCop::Cop::Corrector?]
        source = processed_source
        return super unless block && source.is_a?(ProcessedSource)
        # The cops of rubocop-herb correct the ERB source knowing its tags
        # (e.g. Herb/EmptyErbTag removes ERB tags, which joins the HTML parts around them)
        return super if cop_name.start_with?("Herb/")

        super do |corrector|
          # Correct on a candidate corrector first; the given corrector is left empty if rejected
          candidate = ::RuboCop::Cop::Corrector.new(corrector.source_buffer)
          block.call(candidate)
          accepted = acceptable_correction(source, candidate)
          corrector.merge!(accepted) if accepted
        end
      end

      # The candidate trimmed to the content of ERB tags if it is valid, or the candidate if it is valid
      # The trimmed one is preferred, as the candidate may be accepted but join ERB tags
      # (e.g. `<% a %> <% 1 %>` into `<% a  %>` by removing `1` along with the whitespace on its left)
      # @rbs source: ProcessedSource
      # @rbs candidate: ::RuboCop::Cop::Corrector
      def acceptable_correction(source, candidate) #: ::RuboCop::Cop::Corrector?
        validator = source.correction_validator
        trimmed = source.correction_adjuster.trim(candidate)
        [trimmed, candidate].compact.find { validator.valid?(_1) }
      end
    end
  end
end

RuboCop::Cop::Base.prepend(RuboCop::Herb::CopCorrectionGuard)
