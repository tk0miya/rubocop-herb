# frozen_string_literal: true

module RuboCop
  module Herb
    # Data class for character-based range (not byte-based)
    # Used for mapping positions in text where character indexing is needed
    CharRange = Data.define(
      :from, #: Integer
      :to    #: Integer
    )
  end
end
