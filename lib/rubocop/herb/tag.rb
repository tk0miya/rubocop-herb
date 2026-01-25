# frozen_string_literal: true

module RuboCop
  module Herb
    # Data class for storing tag information with character positions
    # Used for mapping simplified Ruby code back to original HTML/text/ERB
    Tag = Data.define(
      :char_from, #: Integer -- start character position
      :char_to, #: Integer -- end character position
      :restore_source #: bool
    )
  end
end
