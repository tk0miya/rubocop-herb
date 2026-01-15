# frozen_string_literal: true

require "lint_roller"
module RuboCop
  module Herb
    class Plugin < LintRoller::Plugin
      # @rbs override
      def initialize(config = {})
        super
        Configuration.setup(config)
      end

      # @rbs override
      def about
        LintRoller::About.new(
          name: "rubocop-herb",
          version: RuboCop::Herb::VERSION,
          homepage: "https://github.com/tk0miya/rubocop-herb",
          description: "RuboCop plugin for HTML + ERB files"
        )
      end

      # @rbs override
      def supported?(context)
        context.engine == :rubocop
      end

      # @rbs override
      def rules(_context)
        ::RuboCop::Runner.ruby_extractors.unshift(Extractor)

        LintRoller::Rules.new(
          type: :object,
          config_format: :rubocop,
          value: Configuration.to_rubocop_config
        )
      end
    end
  end
end
