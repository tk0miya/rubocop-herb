# frozen_string_literal: true

module RuboCop
  module Herb
    # Data class for storing tag information
    # Used for mapping simplified Ruby code back to original HTML/text/ERB
    # Uses character-based positions (not byte-based) for compatibility with Parser gem
    Tag = Data.define(
      :range, #: CharRange
      :restore_source #: bool
    )
  end
end
