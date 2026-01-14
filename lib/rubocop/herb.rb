# frozen_string_literal: true

require_relative "herb/converter"
require_relative "herb/erb_node_collector"
require_relative "herb/extractor"
require_relative "herb/version"

module RuboCop
  module Herb
    class Error < StandardError; end
    # Your code goes here...
  end
end
