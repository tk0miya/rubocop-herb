# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe RuboCop::Cop::Herb::Lint do
  let(:cop) { described_class.new(RuboCop::Config.new("Herb/Lint" => { "NodeCommand" => node_command })) }
  let(:node_command) { "node" }
  let(:project_root) { Dir.mktmpdir }

  before do
    allow(RuboCop::ConfigFinder).to receive(:project_root).and_return(project_root)
    write(".herb.yml", "version: 0.11.0\n")
    write("node_modules/@herb-tools/linter/package.json", %({"version": "0.11.0"}))
    write(".herb/rules/my_rule.mjs", "export default class MyRule {}\n")
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
      before { write(".herb.yml", "version: 0.11.0\nframework: actionview\n") }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when herb-lint is updated" do
      before { write("node_modules/@herb-tools/linter/package.json", %({"version": "0.12.0"})) }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when a custom rule is changed" do
      before { write(".herb/rules/my_rule.mjs", "export default class MyChangedRule {}\n") }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when Node.js is installed in PATH" do
      let!(:checksum_before) do
        stub_const("ENV", ENV.to_h.merge("PATH" => File.join(project_root, "bin")))
        cop.external_dependency_checksum
      end

      before do
        write("bin/node", "#!/bin/sh\n")
        FileUtils.chmod(0o755, File.join(project_root, "bin/node"))
      end

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when Node.js is upgraded via a symlink" do
      let(:node_command) { File.join(project_root, "bin/node") }
      let!(:checksum_before) do
        write("versions/1/node", "#!/bin/sh\n")
        FileUtils.chmod(0o755, File.join(project_root, "versions/1/node"))
        FileUtils.mkdir_p(File.join(project_root, "bin"))
        File.symlink(File.join(project_root, "versions/1/node"), node_command)
        cop.external_dependency_checksum
      end

      before do
        write("versions/2/node", "#!/bin/sh\n")
        FileUtils.chmod(0o755, File.join(project_root, "versions/2/node"))
        File.unlink(node_command)
        File.symlink(File.join(project_root, "versions/2/node"), node_command)
      end

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when Node.js is installed at the path of NodeCommand" do
      let(:node_command) { File.join(project_root, "bin/node") }

      before do
        write("bin/node", "#!/bin/sh\n")
        FileUtils.chmod(0o755, node_command)
      end

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end

    context "when a custom rule is added" do
      before { write(".herb/rules/nested/other_rule.js", "export default class OtherRule {}\n") }

      it "returns a different checksum" do
        expect(subject).to be false
      end
    end
  end
end
