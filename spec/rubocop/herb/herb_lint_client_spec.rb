# frozen_string_literal: true

require "tmpdir"

RSpec.describe RuboCop::Herb::HerbLintClient do
  let(:client) { described_class.new(node_command: "node", project_root:) }
  let(:project_root) { File.expand_path("../../fixtures/herb_lint", __dir__) }

  after { client.close }

  describe ".for" do
    subject { described_class.for(node_command: "node", project_root:, checksum:) }

    let(:checksum) { "checksum" }
    let!(:client) { described_class.for(node_command: "node", project_root:, checksum: "checksum") }

    context "when called again with the same checksum in the same process" do
      it "returns the same client" do
        expect(subject.equal?(client)).to be true
      end
    end

    context "when called with a different checksum" do
      let(:checksum) { "changed" }

      it "returns a new client" do
        expect(subject.equal?(client)).to be false
        expect(subject.checksum).to eq "changed"
      end
    end

    context "when called in a forked process" do
      before { allow(Process).to receive(:pid).and_return(Process.pid + 1) }

      it "returns a new client" do
        expect(subject.equal?(client)).to be false
      end
    end
  end

  describe "#report_startup_error_on?" do
    subject { %w[a.html.erb b.html.erb a.html.erb].map { client.report_startup_error_on?(_1) } }

    it "returns true only for the first file asked" do
      expect(subject).to eq [true, false, true]
    end
  end

  describe "#lint" do
    subject { client.lint(File.join(project_root, path), source) }

    let(:path) { "app/views/test.html.erb" }
    let(:source) { "<div>\n  <p>日本語😀<img src=\"logo.png\"></p>\n</div>\n" }

    context "when the file has herb-lint offenses" do
      it "returns offenses with character-based locations" do
        expect(subject).to eq [
          described_class::Offense.new(
            rule: "html-img-require-alt",
            message: "Missing required `alt` attribute on `<img>` tag. " \
                     "Add `alt=\"\"` for decorative images or `alt=\"description\"` for informative images.",
            severity: "warning",
            start_line: 2, start_column: 10, end_line: 2, end_column: 13
          )
        ]
      end
    end

    context "when multiple files are linted" do
      subject { 2.times.map { client.lint(File.join(project_root, path), source).map(&:rule) } }

      it "reuses the server process" do
        allow(Open3).to receive(:popen2).and_call_original
        expect(subject).to eq [["html-img-require-alt"], ["html-img-require-alt"]]
        expect(Open3).to have_received(:popen2).once
      end
    end

    context "when the file is excluded in .herb.yml" do
      let(:path) { "excluded/test.html.erb" }

      it "returns no offenses" do
        expect(subject).to eq []
      end
    end

    context "when herb-lint writes to stdout" do
      let(:project_root) { File.expand_path("../../fixtures/herb_lint_noisy", __dir__) }

      it "sends the output to stderr not to break the communication with the server" do
        expect { expect(subject.map(&:rule)).to eq ["html-img-require-alt"] }
          .to output("noisy output from a custom rule\n").to_stderr_from_any_process
      end
    end

    context "when the server process has exited" do
      before do
        client.lint(File.join(project_root, path), source)
        wait_thread = client.send(:server).wait_thread
        Process.kill(:KILL, wait_thread.pid)
        wait_thread.join
      end

      it "raises an error and respawns the server on the next request" do
        expect { subject }.to raise_error(described_class::Error, "herb-lint server exited unexpectedly")
        expect(client.lint(File.join(project_root, path), source).map(&:rule)).to eq ["html-img-require-alt"]
      end
    end

    context "when @herb-tools/linter is not installed" do
      let(:project_root) { Dir.mktmpdir }

      after { FileUtils.remove_entry(project_root) }

      it "raises an error without retrying to start the server" do
        allow(Open3).to receive(:popen2).and_call_original
        message = "@herb-tools/linter is not installed in #{project_root}"
        lint = -> { client.lint(File.join(project_root, path), source) }
        expect { lint.call }.to raise_error(described_class::StartupError, message)
        expect { lint.call }.to raise_error(described_class::StartupError, message)
        expect(Open3).to have_received(:popen2).once
      end
    end

    context "when the node command is not found" do
      let(:client) { described_class.new(node_command: "no-such-node", project_root:) }

      it "raises an error" do
        expect { subject }.to raise_error(described_class::StartupError, "Node.js command not found: no-such-node")
      end
    end
  end
end
