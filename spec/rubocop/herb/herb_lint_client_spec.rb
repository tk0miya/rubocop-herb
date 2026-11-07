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
            start_line: 2, start_column: 10, end_line: 2, end_column: 13, fix: nil
          )
        ]
      end
    end

    context "when the file has autocorrectable herb-lint offenses" do
      let(:source) { "<p>日本語😀<IMG src=\"logo.png\" alt=\"\"></p>\n" }

      it "returns offenses with the fixes at character-based positions" do
        expect(subject).to eq [
          described_class::Offense.new(
            rule: "html-tag-name-lowercase",
            message: "Opening tag name `<IMG>` should be lowercase. Use `<img>` instead.",
            severity: "error",
            start_line: 1, start_column: 8, end_line: 1, end_column: 11,
            fix: described_class::Fix.new(begin_pos: 8, end_pos: 11, replacement: "img")
          )
        ]
      end
    end

    context "when the file has herb-lint offenses autocorrectable only unsafely" do
      subject { client.lint(File.join(project_root, path), source, unsafe_fixes:).map { [_1.rule, _1.fix] } }

      let(:source) { "<p>Tom & Jerry</p>\n" }

      context "without unsafe fixes" do
        let(:unsafe_fixes) { false }

        it "returns offenses without the fixes" do
          expect(subject).to eq [["html-no-unescaped-entities", nil]]
        end
      end

      context "with unsafe fixes" do
        let(:unsafe_fixes) { true }

        it "returns offenses with the unsafe fixes" do
          expect(subject).to eq [
            ["html-no-unescaped-entities",
             described_class::Fix.new(begin_pos: 8, end_pos: 8, replacement: "amp;")]
          ]
        end
      end
    end

    context "when the default external encoding is not UTF-8" do
      let(:source) { "<p><%= \"日本語\" %></p>\n" }

      around do |example|
        default_external = Encoding.default_external
        verbose = $VERBOSE
        $VERBOSE = nil # Silence the warning on setting the default external encoding
        Encoding.default_external = Encoding::US_ASCII
        example.run
      ensure
        Encoding.default_external = default_external
        $VERBOSE = verbose
      end

      it "talks with the server in UTF-8" do
        expect(subject.map { [_1.message, _1.fix&.replacement] }).to eq [
          ["Avoid outputting string literal `\"日本語\"`. Use `日本語` instead.", "日本語"]
        ]
      end
    end

    context "when a rule reported once per run is reported" do
      subject do
        %w[a.html.erb b.html.erb a.html.erb].map { client.lint(File.join(project_root, _1), "<p></p>\n").map(&:rule) }
      end

      let(:project_root) { File.expand_path("../../fixtures/herb_lint_no_framework", __dir__) }

      it "reports it only on the first file, including when it is linted again (e.g. autocorrection)" do
        expect(subject).to eq [["herb-config-framework-option"], [], ["herb-config-framework-option"]]
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
