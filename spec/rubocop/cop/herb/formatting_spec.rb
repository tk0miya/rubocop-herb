# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe RuboCop::Cop::Herb::Formatting do
  let(:cop) { described_class.new(RuboCop::Config.new("Herb/Formatting" => { "NodeCommand" => "node" })) }
  let(:project_root) { Dir.mktmpdir }

  before do
    allow(RuboCop::ConfigFinder).to receive(:project_root).and_return(project_root)
    write(".herb.yml", "version: 0.11.0\nformatter:\n  enabled: true\n")
    write("node_modules/@herb-tools/formatter/package.json", %({"version": "0.11.0"}))
    write(".herb/rewriters/my_rewriter.mjs", "export default class MyRewriter {}\n")
  end

  after { FileUtils.remove_entry(project_root) }

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(File.join(project_root, path)))
    File.write(File.join(project_root, path), content)
  end

  describe "#external_dependency_checksum" do
    subject { cop.external_dependency_checksum == checksum_before }

    let!(:checksum_before) { cop.external_dependency_checksum }

    context "when nothing is changed" do
      it "returns the same checksum" do
        expect(subject).to be true
      end
    end

    context "when .herb.yml is changed" do
      before { write(".herb.yml", "version: 0.11.0\nformatter:\n  enabled: false\n") }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when herb-format is updated" do
      before { write("node_modules/@herb-tools/formatter/package.json", %({"version": "0.12.0"})) }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when a custom rewriter is changed" do
      before { write(".herb/rewriters/my_rewriter.mjs", "export default class MyChangedRewriter {}\n") }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when .herb.yml in a parent directory of the project root is changed" do
      let!(:checksum_before) do
        allow(RuboCop::ConfigFinder).to receive(:project_root).and_return(File.join(project_root, "web"))
        write("web/Gemfile", "")
        cop.external_dependency_checksum
      end

      before { write(".herb.yml", "version: 0.11.0\nformatter:\n  enabled: false\n") }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when a custom rewriter in a parent directory of the project root is changed" do
      let!(:checksum_before) do
        allow(RuboCop::ConfigFinder).to receive(:project_root).and_return(File.join(project_root, "web"))
        write("web/Gemfile", "")
        cop.external_dependency_checksum
      end

      before { write(".herb/rewriters/my_rewriter.mjs", "export default class MyChangedRewriter {}\n") }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when a custom rule of herb-lint is added" do
      before { write(".herb/rules/my_rule.mjs", "export default class MyRule {}\n") }

      it "returns the same checksum, as herb-format does not use it" do
        expect(subject).to be true
      end
    end
  end
end
