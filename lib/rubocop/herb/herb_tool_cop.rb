# frozen_string_literal: true

require "digest/sha1"
require "rubocop"

module RuboCop
  module Herb
    # Shared by the cops running Herb tools on Node.js servers (Herb/Linting and Herb/Formatting).
    # The including cop defines `config_files`, `herb_config_files` and `server_scripts`.
    # @rbs module-self ::RuboCop::Cop::Base
    module HerbToolCop
      # @rbs!
      #   private def config_files: () -> Array[String]
      #   private def herb_config_files: () -> Array[String]
      #   private def server_scripts: () -> Array[String]

      # Invalidates the result cache when Node.js, the Herb tool, its configuration, or its plugins change
      def external_dependency_checksum #: String
        files = glob(config_files, project_root) + glob(herb_config_files, herb_config_dir)
        contents = files.sort.map { "#{_1}\n#{File.read(_1)}" }
        scripts = server_scripts.map { File.read(_1) }
        Digest::SHA1.hexdigest([node_command, node_path.to_s, *scripts, *contents].join("\n"))
      end

      private

      # The absolute paths of the files matching the patterns in the directory
      # @rbs patterns: Array[String]
      # @rbs dir: String
      def glob(patterns, dir) #: Array[String]
        patterns.flat_map { Dir.glob(_1, base: dir) }.map { File.join(dir, _1) }
      end

      # Reports that the Herb tool is not available, once (not for every file)
      # @rbs client: NodeServerClient
      # @rbs path: String -- absolute path of the file
      # @rbs error: NodeServerClient::StartupError
      # @rbs tool: String -- the name of the Herb tool (e.g. "herb-lint")
      # @rbs package: String -- the package of the Herb tool (e.g. "@herb-tools/linter")
      def report_startup_error(client, path, error, tool:, package:) #: void
        source = processed_source
        # Do not consume the report on a file where it would be suppressed by a disable comment
        return unless source.comment_config.cop_enabled_at_line?(self, 1)
        return unless client.report_startup_error_on?(path)

        add_offense_at(source.buffer.line_range(1),
                       "#{tool} is not available: #{error.message}. Set up #{tool} " \
                       "(`npm install --save-dev #{package}`) or disable #{cop_name} cop.",
                       :error)
      end

      # Adds an offense at the range, or to the whole file if the file is empty
      # Formatters fail to read the source line of an offense in an empty file, so Lint/EmptyFile also
      # reports a global offense for it
      # @rbs range: Parser::Source::Range
      # @rbs message: String
      # @rbs severity: Symbol
      # @rbs &block: ? (::RuboCop::Cop::Corrector) -> void
      def add_offense_at(range, message, severity, &block) #: void
        if processed_source.buffer.source.empty?
          add_global_offense(message, severity:)
        elsif block # Steep does not accept passing a nil block to add_offense
          add_offense(range, message:, severity:, &block)
        else
          add_offense(range, message:, severity:)
        end
      end

      # Corrects the source with the fix of the Herb tool.
      # The Herb tool fixes the source as it is, so its fixes may overlap
      # (e.g. both the opening and closing tags of an element are replaced to fix the case of its name).
      # A fix clobbering the fixes applied before is skipped (the offense is reported as not corrected),
      # and is applied in the next iteration of autocorrection, where the Herb tool reports it again if it remains.
      # @rbs corrector: ::RuboCop::Cop::Corrector
      # @rbs fix: NodeServerClient::Fix
      # @rbs applied: ::RuboCop::Cop::Corrector -- the fixes applied so far
      def correct_with(corrector, fix, applied) #: void
        buffer = corrector.source_buffer
        return unless fix.end_pos <= buffer.source.length

        candidate = ::RuboCop::Cop::Corrector.new(buffer)
        candidate.replace(fix_range(fix), fix.replacement)
        # Corrections are applied only when autocorrecting; otherwise they only mark offenses as correctable
        applied.merge!(candidate) if autocorrect?
        corrector.merge!(candidate)
      rescue ::Parser::ClobberingError
        nil
      end

      # @rbs fix: NodeServerClient::Fix
      def fix_range(fix) #: Parser::Source::Range
        Parser::Source::Range.new(processed_source.buffer, fix.begin_pos, fix.end_pos)
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

      # The path of .herb.yml, searched from the project root up to the root directory as Herb tools do;
      # nil if not found
      def herb_config_path #: String?
        dir = project_root
        loop do
          path = File.join(dir, ".herb.yml")
          return path if File.file?(path)

          parent = File.dirname(dir)
          return if parent == dir

          dir = parent
        end
      end

      # The directory of .herb.yml (the project root if not found), to which the configuration of Herb tools
      # (e.g. the patterns in .herb.yml and the directory of custom rules) is relative.
      # It may be above the project root (e.g. a monorepo with .herb.yml at its root)
      def herb_config_dir #: String
        path = herb_config_path
        path ? File.dirname(path) : project_root
      end
    end
  end
end
