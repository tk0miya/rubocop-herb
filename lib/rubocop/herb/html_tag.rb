# frozen_string_literal: true

module RuboCop
  module Herb
    # Data class for storing HTML tag information
    # Used for mapping simplified Ruby code back to original HTML
    HtmlTag = Data.define(
      :range #: ::Herb::Range
    )
  end
end
