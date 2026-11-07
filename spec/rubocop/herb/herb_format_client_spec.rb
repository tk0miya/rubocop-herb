# frozen_string_literal: true

require "tmpdir"

RSpec.describe RuboCop::Herb::HerbFormatClient do
  let(:client) { described_class.new(node_command: "node", project_root:) }
  let(:project_root) { File.expand_path("../../fixtures/herb_format", __dir__) }

  after { client.close }

  def apply(source, fixes)
    fixes.reverse_each.with_object(source.dup) do |fix, result|
      result[fix.begin_pos...fix.end_pos] = fix.replacement
    end
  end

  describe ".for" do
    subject { described_class.for(node_command: "node", project_root:, checksum: "checksum") }

    let!(:lint_client) { RuboCop::Herb::HerbLintClient.for(node_command: "node", project_root:, checksum: "checksum") }

    it "returns the client of the class, not shared with the ones of the other Herb tools" do
      expect([subject.class, lint_client.class]).to eq [described_class, RuboCop::Herb::HerbLintClient]
    end
  end

  describe "#format" do
    subject { client.format(File.join(project_root, path), source) }

    let(:path) { "app/views/test.html.erb" }

    context "when the file is not formatted" do
      let(:source) { "<div><p>日本語😀</p>\n<span><%= @user.name %></span></div>\n" }

      it "returns the fix at character-based positions" do
        expect(subject).to eq [
          described_class::Fix.new(begin_pos: 5, end_pos: 47,
                                   replacement: "\n  <p>日本語😀</p>\n  <span><%= @user.name %></span>\n")
        ]
        expect(apply(source, subject)).to eq <<~ERB
          <div>
            <p>日本語😀</p>
            <span><%= @user.name %></span>
          </div>
        ERB
      end
    end

    context "when lines are only reindented" do
      let(:source) do
        <<~ERB
          <ul>
          <% @items.each do |item| %>
          <li><%= item %></li>
          <% end %>
          </ul>
        ERB
      end

      it "returns a fix for each line" do
        expect(subject).to eq [
          described_class::Fix.new(begin_pos: 5, end_pos: 5, replacement: "  "),
          described_class::Fix.new(begin_pos: 33, end_pos: 33, replacement: "    "),
          described_class::Fix.new(begin_pos: 54, end_pos: 54, replacement: "  ")
        ]
        expect(apply(source, subject)).to eq <<~ERB
          <ul>
            <% @items.each do |item| %>
              <li><%= item %></li>
            <% end %>
          </ul>
        ERB
      end
    end

    # The fix of the line break inserted after `<div>` and the one of the indentation of the next line
    # are at the same position, where RuboCop cannot apply both of them
    context "when the fixes of the lines touch each other" do
      let(:source) { "<div><p>a</p>\n<p>b</p></div>\n" }

      it "joins them into one fix" do
        expect(subject).to eq [
          described_class::Fix.new(begin_pos: 5, end_pos: 22, replacement: "\n  <p>a</p>\n  <p>b</p>\n")
        ]
        expect(apply(source, subject)).to eq "<div>\n  <p>a</p>\n  <p>b</p>\n</div>\n"
      end
    end

    context "when the changed part is too large to compare its lines" do
      let(:source) { "<div>\n#{"<p>a</p>\n" * 2000}</div>\n" }

      it "returns one fix for the part" do
        expect(subject.size).to eq 1
        expect(apply(source, subject)).to eq "<div>\n#{"  <p>a</p>\n" * 2000}</div>\n"
      end
    end

    context "when the file does not end with a newline" do
      let(:source) { "<div>\n  <p>a</p>\n</div>" }

      it "returns the fix adding the newline, as herb-format does" do
        expect(subject).to eq [described_class::Fix.new(begin_pos: 23, end_pos: 23, replacement: "\n")]
      end
    end

    context "when the file is formatted" do
      let(:source) { "<div>\n  <p><%= @user.name %></p>\n</div>\n" }

      it "returns no fixes" do
        expect(subject).to eq []
      end
    end

    context "when the file is empty" do
      let(:source) { "" }

      it "returns no fixes" do
        expect(subject).to eq []
      end
    end

    context "when the file has parse errors" do
      let(:source) { "<div><p>a</div>\n" }

      it "returns no fixes, as herb-format skips the file" do
        expect(subject).to eq []
      end
    end

    context "when the file has the directive to ignore the formatter" do
      let(:source) { "<%# herb:formatter ignore %>\n<div><p>a</p></div>\n" }

      it "returns no fixes" do
        expect(subject).to eq []
      end
    end

    context "when the file is excluded in .herb.yml" do
      let(:path) { "excluded/test.html.erb" }
      let(:source) { "<div><p>a</p></div>\n" }

      it "returns no fixes" do
        expect(subject).to eq []
      end
    end

    context "when the formatter is disabled in .herb.yml" do
      let(:project_root) { File.expand_path("../../fixtures/herb_format_disabled", __dir__) }
      let(:source) { "<div><p>a</p></div>\n" }

      it "returns no fixes" do
        expect(subject).to eq []
      end
    end

    context "when rewriters are configured in .herb.yml" do
      let(:project_root) { File.expand_path("../../fixtures/herb_format_rewriter", __dir__) }
      let(:source) { "<div>\n<p>a</p>\n</div>\n" }

      it "formats the file with the rewriters, skipping the ones not found" do
        expect { expect(apply(source, subject)).to eq "<%# formatted %>\n<div>\n  <p>a</p>\n</div>\n" }
          .to output("herb-format: post-format rewriter \"no-such-rewriter\" not found. Skipping.\n")
          .to_stderr_from_any_process
      end
    end

    context "when the default external encoding is not UTF-8" do
      let(:source) { "<div><p>日本語</p></div>\n" }

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
        expect(apply(source, subject)).to eq "<div>\n  <p>日本語</p>\n</div>\n"
      end
    end

    context "when @herb-tools/formatter is not installed" do
      let(:project_root) { Dir.mktmpdir }
      let(:source) { "<div></div>\n" }

      after { FileUtils.remove_entry(project_root) }

      it "raises an error" do
        expect { subject }.to raise_error(described_class::StartupError,
                                          "@herb-tools/formatter is not installed in #{project_root}")
      end
    end

    context "when the server process has exited" do
      let(:source) { "<div><p>a</p></div>\n" }

      before do
        client.format(File.join(project_root, path), source)
        wait_thread = client.send(:server).wait_thread
        Process.kill(:KILL, wait_thread.pid)
        wait_thread.join
      end

      it "raises an error and respawns the server on the next request" do
        expect { subject }.to raise_error(described_class::Error, "herb-format server exited unexpectedly")
        expect(apply(source, client.format(File.join(project_root, path), source)))
          .to eq "<div>\n  <p>a</p>\n</div>\n"
      end
    end
  end
end
