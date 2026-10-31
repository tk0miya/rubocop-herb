# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Herb::CommentedOutCode do
  include_context "with ERB source"

  context "when a Ruby comment at the end of an ERB tag is followed by an ERB tag on the same line" do
    it "registers an offense at the comment" do
      expect_offense(<<~ERB)
        <% x = 1 # comment %><%= y %>
                 ^^^^^^^^^ This Ruby comment comments out the ERB tags and HTML following it on the same line. Place them on a separate line or use an ERB comment (`<%# %>`).
      ERB
    end
  end

  context "when a Ruby comment comments out the end tag of a control flow ERB tag, making a syntax error" do
    it "registers an offense at the comment" do
      offenses = _investigate(cop, parse_source("<% if x # comment %>a<% end %>\n"))
      expect(offenses.map { [_1.column, _1.column_length, _1.message] }).to eq [[8, 9, described_class::MSG]]
    end
  end

  context "when a Ruby comment with multi-byte characters is followed by an ERB tag" do
    it "registers an offense at the comment" do
      expect_offense(<<~ERB)
        <p>日本語</p><%= "あ" # 日本語のコメント %><%= y %>
                          ^^^^^^^^^^ #{described_class::MSG}
      ERB
    end
  end

  context "when a Ruby comment at the end of an ERB tag is followed by HTML only on the same line" do
    it "registers an offense at the comment" do
      expect_offense(<<~ERB)
        <% x = 1 # comment %><div></div>
                 ^^^^^^^^^ #{described_class::MSG}
      ERB
    end
  end

  context "when a Ruby comment at the end of an ERB tag is followed by an ERB comment only" do
    it "does not register an offense as the ERB comment compiles to no code" do
      expect_no_offenses(<<~ERB)
        <% x = 1 # comment %><%# note %>
      ERB
    end
  end

  context "when a Ruby comment at the end of an ERB tag is not followed by anything on the same line" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <% x = 1 # comment %>
        <%= y %>
      ERB
    end
  end

  context "when a Ruby comment in an ERB tag is followed by a newline in the tag" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <% x = 1 # comment
        %><%= y %>
      ERB
    end
  end

  context "when an ERB comment is followed by an ERB tag on the same line" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%# comment %><%= x %>
      ERB
    end
  end

  context "when a string containing # in an ERB tag is followed by an ERB tag" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%= "# not a comment" %><%= y %>
      ERB
    end
  end

  context "when an escaped ERB tag containing # is followed by an ERB tag" do
    it "does not register an offense as it is text" do
      expect_no_offenses(<<~ERB)
        <%% x # comment %><%= y %>
      ERB
    end
  end
end
