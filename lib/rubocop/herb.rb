# frozen_string_literal: true

# NOTE: require_relative should be sorted in ASCII order
require_relative "herb/configuration"
require_relative "herb/converter"
require_relative "herb/erb_node_collector"
require_relative "herb/extractor"
require_relative "herb/patch/team"
require_relative "herb/plugin"
require_relative "herb/source"
require_relative "herb/version"

module RuboCop
  module Herb
    class Error < StandardError; end
    # Your code goes here...
  end
end
