# frozen_string_literal: true

module RuboCop
  module Herb
    # Data class for storing tag information
    # Used for mapping simplified Ruby code back to original HTML/text/ERB
    Tag = Data.define(
      :range #: ::Herb::Range
    )
  end
end
