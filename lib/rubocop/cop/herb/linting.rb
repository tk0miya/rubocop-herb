# frozen_string_literal: true

require "digest/sha1"
require "rubocop"

module RuboCop
  module Cop
    module Herb
      # Runs herb-lint (@herb-tools/linter) on HTML+ERB files and reports its offenses.
      #
      # This cop requires Node.js and @herb-tools/linter installed in the project
      # (`npm install --save-dev @herb-tools/linter`).
      # If herb-lint is not available, an offense asking to set it up or disable this cop is reported
      # (reported once, not for every file).
      # herb-lint is configured by `.herb.yml` in the project root as usual.
      #
      # @example
      #   # bad
      #   <img src="logo.png">
      #
      #   # good
      #   <img src="logo.png" alt="Logo">
      class Linting < Base
        SEVERITIES = {
          "error" => :error,
          "warning" => :warning,
          "info" => :convention,
          "hint" => :refactor
        }.freeze #: Hash[String, Symbol]

        # Files affecting the result of herb-lint other than the linted file itself
        CONFIG_FILES = [
          ".herb.yml",
          "node_modules/@herb-tools/linter/package.json",
          ".herb/rules/**/*.{js,mjs}"
        ].freeze #: Array[String]

        def on_new_investigation #: void
          source = processed_source
          return unless source.is_a?(::RuboCop::Herb::ProcessedSource)

          path = source.file_path
          return unless path

          lint(source, File.expand_path(path))
        end

        # Invalidates the result cache when Node.js, herb-lint, its configuration, or custom rules change
        def external_dependency_checksum #: String
          files = CONFIG_FILES.flat_map { Dir.glob(_1, base: project_root) }.sort
          contents = files.map { "#{_1}\n#{File.read(File.join(project_root, _1))}" }
          Digest::SHA1.hexdigest([node_command, node_path.to_s, File.read(::RuboCop::Herb::HerbLintClient::SERVER_SCRIPT),
                                  *contents].join("\n"))
        end

        private

        # @rbs source: ::RuboCop::Herb::ProcessedSource
        # @rbs path: String -- absolute path of the file
        def lint(source, path) #: void
          client.lint(path, source.parse_result.code).each do |offense|
            add_offense(offense_range(offense), message: "[#{offense.rule}] #{offense.message}",
                                                severity: SEVERITIES.fetch(offense.severity, :convention))
          end
        rescue ::RuboCop::Herb::HerbLintClient::StartupError => e
          # Do not consume the report on a file where it would be suppressed by a disable comment
          return unless source.comment_config.cop_enabled_at_line?(self, 1)
          return unless client.report_startup_error_on?(path)

          add_offense(source.buffer.line_range(1),
                      message: "herb-lint is not available: #{e.message}. Set up herb-lint " \
                               "(`npm install --save-dev @herb-tools/linter`) or disable Herb/Linting cop.",
                      severity: :error)
        end

        def client #: ::RuboCop::Herb::HerbLintClient
          ::RuboCop::Herb::HerbLintClient.for(node_command:, project_root:, checksum: external_dependency_checksum)
        end

        def node_command #: String
          cop_config.fetch("NodeCommand", "node")
        end

        # The path of the Node.js executable; nil if not installed
        def node_path #: String?
          candidates = if node_command.include?(File::SEPARATOR)
                         [node_command]
                       else
                         ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { File.join(_1, node_command) }
                       end
          # Resolve symlinks to detect upgrades of Node.js installed via symlinks (e.g. Homebrew)
          path = candidates.find { File.file?(_1) && File.executable?(_1) }
          path && File.realpath(path)
        end

        def project_root #: String
          ::RuboCop::ConfigFinder.project_root || Dir.pwd
        end

        # @rbs offense: ::RuboCop::Herb::HerbLintClient::Offense
        def offense_range(offense) #: Parser::Source::Range
          buffer = processed_source.buffer
          begin_pos = position(buffer, offense.start_line, offense.start_column)
          end_pos = position(buffer, offense.end_line, offense.end_column)
          end_pos = begin_pos if end_pos < begin_pos
          Parser::Source::Range.new(buffer, begin_pos, end_pos)
        end

        # @rbs buffer: Parser::Source::Buffer
        # @rbs line: Integer -- 1-based line number
        # @rbs column: Integer -- 0-based column number
        def position(buffer, line, column) #: Integer
          line = line.clamp(1, buffer.last_line)
          line_range = buffer.line_range(line)
          (line_range.begin_pos + column).clamp(line_range.begin_pos, line_range.end_pos)
        end
      end
    end
  end
end
