# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Herb::TrailingRubyComment do
  include_context "with ERB source"

  context "when a Ruby comment at the end of an output tag is not followed by anything" do
    it "registers an offense at the comment as it causes a syntax error" do
      expect_offense(<<~ERB)
        <%= x # comment %>
              ^^^^^^^^^ #{described_class::OUTPUT_TAG_MSG}
      ERB
    end
  end

  context "when a Ruby comment at the end of a raw output tag is not followed by anything" do
    it "registers an offense at the comment as it causes a syntax error" do
      expect_offense(<<~ERB)
        <%== x # comment %>
               ^^^^^^^^^ #{described_class::OUTPUT_TAG_MSG}
      ERB
    end
  end

  context "when an output tag has only a Ruby comment" do
    it "registers an offense at the comment as it causes a syntax error" do
      expect_offense(<<~ERB)
        <%= # comment %>
            ^^^^^^^^^ #{described_class::OUTPUT_TAG_MSG}
      ERB
    end
  end

  context "when a Ruby comment is at the end of an output tag with a block" do
    it "registers an offense at the comment as it causes a syntax error" do
      expect_offense(<<~ERB)
        <%= form_with do |f| # comment %>
                             ^^^^^^^^^ #{described_class::OUTPUT_TAG_MSG}
        <% end %>
      ERB
    end
  end

  context "when a Ruby comment at the end of a code tag is followed by an ERB tag on the same line" do
    it "registers an offense at the comment" do
      expect_offense(<<~ERB)
        <% x = 1 # comment %><%= y %>
                 ^^^^^^^^^ #{described_class::CODE_TAG_MSG}
      ERB
    end
  end

  context "when a Ruby comment comments out the end tag of a control flow ERB tag, making a syntax error" do
    it "registers an offense at the comment" do
      offenses = _investigate(cop, parse_source("<% if x # comment %>a<% end %>\n"))
      expect(offenses.map { [_1.column, _1.column_length, _1.message] }).to eq [[8, 9, described_class::CODE_TAG_MSG]]
    end
  end

  context "when a Ruby comment with multi-byte characters is followed by an ERB tag" do
    it "registers an offense at the comment" do
      expect_offense(<<~ERB)
        <p>日本語</p><% x = "あ" # 日本語のコメント %><%= y %>
                             ^^^^^^^^^^ #{described_class::CODE_TAG_MSG}
      ERB
    end
  end

  context "when a Ruby comment at the end of a code tag is followed by HTML only on the same line" do
    it "registers an offense at the comment" do
      expect_offense(<<~ERB)
        <% x = 1 # comment %><div></div>
                 ^^^^^^^^^ #{described_class::CODE_TAG_MSG}
      ERB
    end
  end

  context "when a Ruby comment at the end of a code tag is not followed by anything on the same line" do
    it "registers an offense at the comment as it breaks when ERB tags or HTML are placed after it" do
      expect_offense(<<~ERB)
        <% x = 1 # comment %>
                 ^^^^^^^^^ #{described_class::CODE_TAG_MSG}
        <%= y %>
      ERB
    end
  end

  context "when a code tag has only a Ruby comment" do
    it "registers an offense at the comment" do
      expect_offense(<<~ERB)
        <% # comment %>
           ^^^^^^^^^ #{described_class::CODE_TAG_MSG}
      ERB
    end
  end

  context "when a Ruby comment in an ERB tag is followed by a newline in the tag" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <% x = 1 # comment
        %><%= y # comment
        %>
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
