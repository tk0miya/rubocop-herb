# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Herb::IgnoredCopDirective do
  include_context "with ERB source"

  context "when an ERB comment containing a rubocop directive is followed by an ERB tag on the same line" do
    it "registers an offense at the directive" do
      expect_offense(<<~ERB)
        <div><%# rubocop:disable Lint/Void %><%= x %></div>
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ rubocop-herb ignores this rubocop directive because ERB tags follow it on the same line. Place them on a separate line.
      ERB
    end
  end

  context "when a multiline ERB comment containing a rubocop directive is followed by an ERB tag" do
    it "registers an offense at the directive" do
      expect_offense(<<~ERB)
        <div>
            <%# rubocop:disable Lint/Void
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
          -- reason %><%= x %>
        </div>
      ERB
    end
  end

  context "when an ERB comment containing a rubocop directive is followed by HTML only on the same line" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%# rubocop:disable Lint/Void %><div>text</div>
      ERB
    end
  end

  context "when an ERB comment containing a rubocop directive follows an ERB tag on the same line" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%= x %><%# rubocop:disable Lint/Void %>
      ERB
    end
  end

  context "when an ERB tag is on the next line of an ERB comment containing a rubocop directive" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%# rubocop:disable Lint/Void %>
        <%= x %>
      ERB
    end
  end

  context "when an ordinary ERB comment is followed by an ERB tag on the same line" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%# comment %><%= x %>
      ERB
    end
  end

  context "when an ERB comment mentioning rubocop without a directive is followed by an ERB tag on the same line" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%# see rubocop docs %><%= x %>
      ERB
    end
  end

  context "when a multiline ERB comment contains a rubocop directive in an indented line" do
    it "registers an offense at the directive" do
      expect_offense(<<~ERB)
        <div>
          <%# note
          ^^^^^^^^ #{described_class::MSG}
          rubocop:disable Lint/Void %><%= x %>
        </div>
      ERB
    end
  end

  context "when an ERB comment containing a rubocop directive is followed by another ERB comment and an ERB tag" do
    it "registers an offense at the directive" do
      expect_offense(<<~ERB)
        <%# rubocop:disable Lint/Void %><%# note %><%= x %>
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
      ERB
    end
  end

  context "when an ignored rubocop directive is in a source with an effective rubocop directive" do
    it "registers an offense at the ignored directive" do
      expect_offense(<<~ERB)
        <%# rubocop:disable Lint/Void %>
        <%# rubocop:disable Lint/Void %><%= x %>
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{described_class::MSG}
      ERB
    end
  end
end
