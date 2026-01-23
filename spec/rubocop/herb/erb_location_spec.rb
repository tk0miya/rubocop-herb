# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ErbLocation do
  describe "#output?" do
    subject { location.output? }

    let(:location) do
      described_class.new(
        type:,
        node: double,
        range: instance_double(Herb::Range, from: 0, to: 10),
        line: 1,
        column: 0
      )
    end

    context "when type is :output" do
      let(:type) { :output }

      it { is_expected.to be true }
    end

    context "when type is :content" do
      let(:type) { :content }

      it { is_expected.to be false }
    end

    context "when type is :comment" do
      let(:type) { :comment }

      it { is_expected.to be false }
    end
  end

  describe "#comment?" do
    subject { location.comment? }

    let(:location) do
      described_class.new(
        type:,
        node: double,
        range: instance_double(Herb::Range, from: 0, to: 10),
        line: 1,
        column: 0
      )
    end

    context "when type is :comment" do
      let(:type) { :comment }

      it { is_expected.to be true }
    end

    context "when type is :content" do
      let(:type) { :content }

      it { is_expected.to be false }
    end

    context "when type is :output" do
      let(:type) { :output }

      it { is_expected.to be false }
    end
  end
end
