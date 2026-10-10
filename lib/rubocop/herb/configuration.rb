# frozen_string_literal: true

module RuboCop
  module Herb
    # Configuration module for managing supported extensions.
    module Configuration
      DEFAULT_EXTENSIONS = %w[.html.erb].freeze #: Array[String]

      # @rbs self.@html_visualization: bool

      # Cops to exclude from ERB files due to inherent incompatibilities
      # with extracted Ruby code from ERB templates.
      EXCLUDED_COPS = [
        "Layout/BlockAlignment", # Output tag markers shift block start; ERB end may follow HTML
        "Layout/CommentIndentation", # ERB comment to Ruby comment conversion shifts column position
        "Layout/EndAlignment", # Ruby end keywords in ERB may align with HTML structure, not Ruby
        "Layout/ExtraSpacing", # Whitespace padding preserves positions but creates extra spaces
        "Layout/IndentationConsistency", # Ruby code in ERB may be aligned differently
        "Layout/IndentationWidth", # Ruby code in ERB may have different indentation width
        "Layout/InitialIndentation", # ERB code may start at any indentation level within HTML
        "Layout/LeadingEmptyLines", # ERB files may not start with Ruby code
        "Layout/TrailingEmptyLines", # ERB files may not end with Ruby code
        "Layout/TrailingWhitespace", # Whitespace padding preserves positions but creates trailing spaces
        "Metrics/BlockLength", # ERB blocks often contain substantial HTML content
        "Style/FrozenStringLiteralComment", # ERB files don't support frozen string literal comments
        "Style/Semicolon" # Semicolons are inserted between ERB tags on the same line
      ].freeze #: Array[String]

      class << self
        # @rbs config: Hash[String, untyped]
        def setup(config) #: void
          @supported_extensions = config["extensions"] || DEFAULT_EXTENSIONS
          @html_visualization = config["html_visualization"] || false
        end

        def html_visualization? #: bool
          @html_visualization
        end

        # @rbs path: String
        def supported_file?(path) #: bool
          supported_extensions.any? { path.end_with?(_1) }
        end

        def to_rubocop_config #: Hash[String, untyped]
          # Include both relative and absolute path patterns for glob matching
          globs = supported_extensions.flat_map { ["**/*#{_1}", "/**/*#{_1}"] }

          config = { "AllCops" => { "Include" => globs }, "Herb/Lint" => herb_lint_config(globs) }
          EXCLUDED_COPS.each do |cop|
            config[cop] = { "Exclude" => globs }
          end
          config
        end

        private

        # Default configuration of Herb/Lint cop (enabled; it reports an error if herb-lint is not set up)
        # @rbs globs: Array[String]
        def herb_lint_config(globs) #: Hash[String, untyped]
          {
            "Description" => "Runs herb-lint (@herb-tools/linter) on HTML+ERB files.",
            "Enabled" => true,
            "Include" => globs,
            "NodeCommand" => "node"
          }
        end

        # rbs-inline emits attr_reader as an instance reader regardless of
        # nesting inside `class << self`, so declare the singleton reader by hand.
        # @rbs skip
        attr_reader :supported_extensions #: Array[String]

        # @rbs!
        #   private attr_reader self.supported_extensions: Array[String]
      end
    end
  end
end
