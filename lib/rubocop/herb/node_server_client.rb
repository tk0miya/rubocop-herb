# frozen_string_literal: true

require "json"
require "open3"

module RuboCop
  module Herb
    # Base class of the clients of the servers running Herb tools on Node.js
    # (HerbLintClient for herb-lint, and HerbFormatClient for herb-format).
    #
    # Spawning Node.js and loading Herb tools takes a few hundred milliseconds,
    # so a server process is spawned once and reused for all files.
    # The server is spawned lazily on the first request in each process;
    # forked processes (`rubocop --parallel`) spawn their own one.
    class NodeServerClient
      class Error < StandardError; end
      # Raised when the server has exited or returned an invalid response
      class BrokenServer < Error; end
      # Raised when the Herb tool is not available (e.g. Node.js or the package of the tool is not installed)
      class StartupError < Error; end

      # A fix of the Herb tool, as a replacement of the source.
      # Positions are 0-based character offsets of the source given to the request.
      Fix = Data.define(
        :begin_pos,   #: Integer
        :end_pos,     #: Integer
        :replacement  #: String
      )

      # A running server process and the pipes connected to it
      Server = Data.define(
        :stdin,       #: IO
        :stdout,      #: IO
        :wait_thread  #: Process::Waiter
      )

      # The script shared by the servers (loaded by them)
      COMMON_SCRIPT = File.expand_path("node_server.cjs", __dir__.not_nil!) #: String

      class << self
        # Returns the client of this class shared in the current process
        # @rbs node_command: String
        # @rbs project_root: String
        # @rbs checksum: String -- digest of the configuration; the server is respawned when it changes
        def for(node_command:, project_root:, checksum:) #: instance
          # Clients inherited from the parent process share pipes with it; do not reuse them
          reset_clients if pid != Process.pid

          key = [node_command, project_root] #: [String, String]
          client = clients[key]
          return client if client && client.checksum == checksum

          # The server loads the configuration only on startup, so respawn it
          # when the configuration is changed in long-running processes (e.g. rubocop --lsp)
          client&.close
          # Steep types `new` of the base class, not of the subclass the method is called on
          clients[key] = _ = new(node_command:, project_root:, checksum:)
        end

        # The scripts of the server, whose changes invalidate the result cache
        def server_scripts #: Array[String]
          [COMMON_SCRIPT]
        end

        private

        def reset_clients #: void
          @clients = {}
          @pid = Process.pid
        end

        # rbs-inline emits attr_reader as an instance reader regardless of
        # nesting inside `class << self`, so declare the singleton readers by hand.
        # @rbs skip
        attr_reader :clients #: Hash[[String, String], untyped]
        # @rbs skip
        attr_reader :pid #: Integer?

        # @rbs!
        #   private attr_reader self.clients: Hash[[String, String], untyped]
        #   private attr_reader self.pid: Integer?
      end

      attr_reader :node_command #: String
      attr_reader :project_root #: String
      attr_reader :checksum #: String?

      # @rbs node_command: String -- the Node.js executable
      # @rbs project_root: String -- the directory to resolve the packages of Herb tools and .herb.yml from
      # @rbs checksum: String? -- digest of the configuration the server is started with
      def initialize(node_command:, project_root:, checksum: nil) #: void
        @node_command = node_command
        @project_root = project_root
        @checksum = checksum
        @server = nil
        @startup_error = nil
        @startup_error_report_path = nil
      end

      # Returns whether the startup error should be reported on the file.
      # It is true only for the first file asked so that the error is reported only once, not for every file.
      # The first file is answered true again because long-running processes (e.g. rubocop --server and
      # rubocop --lsp) inspect it again; otherwise the error would disappear from it.
      # @rbs path: String -- absolute path of the file to report the error on
      def report_startup_error_on?(path) #: bool
        claimed_path = startup_error_report_path
        return claimed_path == path if claimed_path

        @startup_error_report_path = path
        true
      end

      def close #: void
        server = self.server
        return unless server

        server.stdin.close
        server.stdout.close
        server.wait_thread.join
        @server = nil
      end

      private

      attr_reader :server #: Server?
      attr_reader :startup_error #: StartupError?
      attr_reader :startup_error_report_path #: String?

      # The name of the Herb tool for messages (e.g. "herb-lint")
      def tool_name #: String
        raise NotImplementedError
      end

      # The script of the server
      def server_script #: String
        raise NotImplementedError
      end

      # Sends the request to the server and returns the response.
      # Raises StartupError if the server fails to start.
      # The failure is remembered, so the server is not respawned for the following calls.
      # @rbs message: Hash[Symbol, untyped]
      def request(message) #: Hash[String, untyped]
        server = self.server || start
        begin
          server.stdin.puts(JSON.generate(message))
          server.stdin.flush
          response = read_response(server.stdout)
        rescue BrokenServer, Errno::EPIPE, IOError => e
          # Respawn the server on the next request
          close
          raise Error, e.is_a?(BrokenServer) ? e.message : "#{tool_name} server exited unexpectedly"
        end
        raise Error, "#{tool_name} failed: #{response["error"]}" if response["error"]

        response
      end

      def start #: Server
        error = startup_error
        raise error if error

        @server = spawn_server
      rescue Error, SystemCallError => e
        message = e.is_a?(Errno::ENOENT) ? "Node.js command not found: #{node_command}" : e.message
        # Remember the failure not to respawn the server for each file
        error = StartupError.new(message)
        @startup_error = error
        raise error
      end

      def spawn_server #: Server
        stdin, stdout, wait_thread = Open3.popen2(node_command, server_script, project_root)
        # The server talks in UTF-8 regardless of the locale (the default external encoding may be US-ASCII)
        stdin.set_encoding(Encoding::UTF_8)
        stdout.set_encoding(Encoding::UTF_8)
        server = Server.new(stdin:, stdout:, wait_thread:)
        response = read_response(stdout)
        return server unless response["error"]

        stdin.close
        stdout.close
        wait_thread.join
        raise Error, response["error"]
      end

      # @rbs stdout: IO
      def read_response(stdout) #: Hash[String, untyped]
        line = stdout.gets
        raise BrokenServer, "#{tool_name} server exited unexpectedly" unless line

        JSON.parse(line)
      rescue JSON::ParserError
        raise BrokenServer, "#{tool_name} server returned an invalid response: #{line}"
      end

      # @rbs fix: Hash[String, untyped]?
      def build_fix(fix) #: Fix?
        return unless fix

        Fix.new(
          begin_pos: fix.fetch("start"),
          end_pos: fix.fetch("end"),
          replacement: fix.fetch("replacement")
        )
      end
    end
  end
end
