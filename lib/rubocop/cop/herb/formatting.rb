# frozen_string_literal: true

require "rubocop"
require "yaml"

module RuboCop
  module Cop
    module Herb
      # Checks that HTML+ERB files are formatted as herb-format (@herb-tools/formatter) formats them,
      # and formats them by autocorrection.
      #
      # This cop does nothing unless the formatter is enabled in `.herb.yml` (`formatter.enabled: true`),
      # as herb-format does nothing unless it is enabled. So it is enabled by default,
      # and `.herb.yml` decides whether to format files (and which files with `formatter.exclude`).
      # When the formatter is enabled, this cop requires Node.js and @herb-tools/formatter installed in the project
      # (`npm install --save-dev @herb-tools/formatter`).
      # If herb-format is not available, an offense asking to set it up or disable this cop is reported
      # (reported once, not for every file).
      #
      # Each part of the file changed by the formatting (e.g. the indentation of a line) is reported as an offense.
      # The autocorrection is unsafe, as herb-format is in experimental preview,
      # and changes the whitespace in HTML, which may change how the page is rendered.
      #
      # @example
      #   # bad
      #   <div><p><%= @user.name %></p></div>
      #
      #   # good
      #   <div>
      #     <p><%= @user.name %></p>
      #   </div>
      class Formatting < Base
        include ::RuboCop::Herb::HerbToolCop
        extend AutoCorrector

        MSG = "Format the template as herb-format does."

        # Files in the project root affecting the result of herb-format other than the formatted file itself
        CONFIG_FILES = [
          "node_modules/@herb-tools/formatter/package.json"
        ].freeze #: Array[String]

        # Files in the directory of .herb.yml affecting the result of herb-format
        HERB_CONFIG_FILES = [
          ".herb.yml",
          ".herb/rewriters/**/*.mjs"
        ].freeze #: Array[String]

        def on_new_investigation #: void
          source = processed_source
          return unless source.is_a?(::RuboCop::Herb::ProcessedSource)

          path = source.file_path
          return unless path
          # Do not spawn the server (nor require Node.js) unless the formatter is enabled
          return unless formatter_enabled?

          format(source, File.expand_path(path))
        end

        private

        # @rbs source: ::RuboCop::Herb::ProcessedSource
        # @rbs path: String -- absolute path of the file
        def format(source, path) #: void
          # The fixes applied so far in this investigation
          applied = ::RuboCop::Cop::Corrector.new(source.buffer)
          client.format(path, source.parse_result.code).each do |fix|
            add_offense(fix_range(fix)) { correct_with(_1, fix, applied) }
          end
        rescue ::RuboCop::Herb::HerbFormatClient::StartupError => e
          report_startup_error(client, path, e, tool: "herb-format", package: "@herb-tools/formatter")
        end

        # Whether the formatter is enabled in .herb.yml (`formatter.enabled`; disabled by default).
        # An invalid .herb.yml is left to herb-format to report the error.
        def formatter_enabled? #: bool
          path = herb_config_path
          return false unless path

          config = YAML.safe_load_file(path, aliases: true) # Herb accepts anchors and aliases
          formatter = config["formatter"] if config.is_a?(Hash)
          formatter.is_a?(Hash) && formatter["enabled"] == true
        rescue Psych::Exception
          true
        end

        def client #: ::RuboCop::Herb::HerbFormatClient
          ::RuboCop::Herb::HerbFormatClient.for(node_command:, project_root:, checksum: external_dependency_checksum)
        end

        def config_files #: Array[String]
          CONFIG_FILES
        end

        def herb_config_files #: Array[String]
          HERB_CONFIG_FILES
        end

        def server_scripts #: Array[String]
          ::RuboCop::Herb::HerbFormatClient.server_scripts
        end
      end
    end
  end
end
