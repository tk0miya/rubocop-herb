# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ErbNode do
  describe ".escaped?" do
    subject { described_class.escaped?(node) }

    let(:node) { Herb.parse(code).value.children.first }

    context "with an escaped ERB tag" do
      let(:code) { "<%% x %>" }

      it { is_expected.to be true }
    end

    context "with an escaped output ERB tag" do
      let(:code) { "<%%= x %>" }

      it { is_expected.to be true }
    end

    context "with an escaped ERB if tag" do
      let(:code) { "<%% if x %><%% end %>" }

      it { is_expected.to be true }
    end

    context "with an output ERB tag" do
      let(:code) { "<%= x %>" }

      it { is_expected.to be false }
    end

    context "with an HTML element" do
      let(:code) { "<p>x</p>" }

      it { is_expected.to be false }
    end
  end
end
