# frozen_string_literal: true

require "rubocop"

# Monkey patch to fix autocorrect with ruby_extractors
# RuboCop uses merge! when offset == 0, but import! is needed
# when the source_buffer is different (as with extracted Ruby from ERB)
#
# This issue has been reported to RuboCop:
# https://github.com/rubocop/rubocop/issues/14138
module RuboCop
  module Cop
    class Team
      private

      # Override to always use import! instead of merge!
      # This is necessary because extracted Ruby code has a different source_buffer
      # than the original ERB file, even when the offset is 0.
      def collate_corrections(report, offset:, original:)
        corrector = Corrector.new(original)

        each_corrector(report) do |to_merge|
          suppress_clobbering do
            # Always use import! to handle different source buffers
            corrector.import!(to_merge, offset: offset)
          end
        end

        corrector
      end
    end
  end
end
