# frozen_string_literal: true

module RuboCop
  module Herb
    # Configuration module for managing supported extensions.
    module Configuration
      DEFAULT_EXTENSIONS = %w[.html.erb].freeze #: Array[String]

      # Cops to exclude from ERB files due to inherent incompatibilities
      # with extracted Ruby code from ERB templates.
      EXCLUDED_COPS = [
        "Layout/CommentIndentation", # ERB comment to Ruby comment conversion shifts column position
        "Layout/ExtraSpacing", # Whitespace padding preserves positions but creates extra spaces
        "Layout/IndentationWidth", # Ruby code in ERB may have different indentation width
        "Layout/InitialIndentation", # ERB code may start at any indentation level within HTML
        "Layout/LeadingEmptyLines", # ERB files may not start with Ruby code
        "Layout/TrailingEmptyLines", # ERB files may not end with Ruby code
        "Layout/TrailingWhitespace", # Whitespace padding preserves positions but creates trailing spaces
        "Style/FrozenStringLiteralComment", # ERB files don't support frozen string literal comments
        "Style/IfWithSemicolon", # Semicolons are inserted between ERB tags on the same line
        "Style/Semicolon" # Semicolons are inserted between ERB tags on the same line
      ].freeze #: Array[String]

      # Cops temporarily excluded due to HTML parts being replaced with whitespace.
      # These may be removed once HTML visualization is implemented.
      HTML_RELATED_EXCLUDED_COPS = [
        "Lint/EmptyConditionalBody", # Conditional bodies may contain only HTML (no Ruby code)
        "Lint/EmptyWhen", # When bodies may contain only HTML (no Ruby code)
        "Style/EmptyElse" # Else branches may contain only HTML (no Ruby code)
      ].freeze #: Array[String]

      # @rbs self.@supported_extensions: Array[String]

      class << self
        # @rbs config: Hash[String, untyped]
        def setup(config) #: void
          @supported_extensions = config["extensions"] || DEFAULT_EXTENSIONS
        end

        # @rbs path: String
        def supported_file?(path) #: bool
          @supported_extensions.any? { |ext| path.end_with?(ext) }
        end

        def to_rubocop_config #: Hash[String, untyped]
          # Include both relative and absolute path patterns for glob matching
          globs = @supported_extensions.flat_map { |ext| ["**/*#{ext}", "/**/*#{ext}"] }

          config = { "AllCops" => { "Include" => globs } }
          (EXCLUDED_COPS + HTML_RELATED_EXCLUDED_COPS).each do |cop|
            config[cop] = { "Exclude" => globs }
          end
          config
        end
      end
    end
  end
end
