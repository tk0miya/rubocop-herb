# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Herb::EmptyErbTag do
  include_context "with ERB source"

  context "when an empty ERB tag is alone on its line" do
    it "registers an offense and removes the line" do
      expect_offense(<<~ERB)
        <p>a</p>
          <% %>
          ^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
        <p>b</p>
      ERB
    end
  end

  context "when an empty ERB tag follows multi-byte characters" do
    it "registers an offense and removes the line" do
      expect_offense(<<~ERB)
        <p>日本語🍣</p>
        <% %>
        ^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>日本語🍣</p>
        <p>b</p>
      ERB
    end
  end

  context "when an empty ERB tag is next to HTML" do
    it "registers an offense and removes the tag" do
      expect_offense(<<~ERB)
        <p><% %></p>
           ^^^^^ Remove the empty ERB tag.
      ERB

      expect_correction(<<~ERB)
        <p></p>
      ERB
    end
  end

  context "when empty ERB tags are next to each other" do
    it "registers offenses and removes the tags" do
      expect_offense(<<~ERB)
        <p>a</p><% %><% %>
                ^^^^^ Remove the empty ERB tag.
                     ^^^^^ Remove the empty ERB tag.
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
      ERB
    end
  end

  context "when empty ERB tags are alone on their line" do
    it "registers offenses and removes the line" do
      expect_offense(<<~ERB)
        <p>a</p>
        <% %> <%# %>
        ^^^^^ Remove the empty ERB tag.
              ^^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
        <p>b</p>
      ERB
    end
  end

  context "when empty ERB tags end the line after HTML" do
    it "registers offenses and removes the tags and the whitespace before them" do
      expect_offense(<<~ERB)
        <p>a</p> <% %>  <%# %>
                 ^^^^^ Remove the empty ERB tag.
                        ^^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
        <p>b</p>
      ERB
    end
  end

  context "when an empty ERB tag with a trim marker `-%>` ends the line after HTML" do
    it "registers an offense and removes the tag and the newline trimmed by the marker" do
      expect_offense(<<~ERB)
        <p>a</p> <% -%>
                 ^^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p> <p>b</p>
      ERB
    end
  end

  context "when an empty ERB tag with a trim marker `-%>` is followed by an empty ERB tag at the line end" do
    it "registers offenses and removes the tags and the whitespace before them" do
      expect_offense(<<~ERB)
        <p>a</p> <% -%> <% %>
                 ^^^^^^ Remove the empty ERB tag.
                        ^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
        <p>b</p>
      ERB
    end
  end

  context "when an empty ERB tag with a trim marker `<%-` follows another empty ERB tag" do
    it "registers offenses and removes the tags only" do
      expect_offense(<<~ERB)
        <% %> <%- %>x
        ^^^^^ Remove the empty ERB tag.
              ^^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      # The space between the tags is rendered, as `<%-` trims only the indentation
      expect_correction(<<~ERB)
         x
        <p>b</p>
      ERB
    end
  end

  context "when an empty ERB tag spans multiple lines" do
    it "registers an offense and removes the lines" do
      expect_offense(<<~ERB)
        <p>a</p>
        <%
        ^^ Remove the empty ERB tag.
        %>
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
        <p>b</p>
      ERB
    end
  end

  context "when an empty ERB tag with a trim marker `-%>` is next to HTML" do
    it "registers an offense and removes the tag and the newline trimmed by the marker" do
      expect_offense(<<~ERB)
        <p>a</p><% -%>
                ^^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p><p>b</p>
      ERB
    end
  end

  context "when an empty ERB tag with a trim marker `<%-` is followed by HTML" do
    it "registers an offense and removes the tag and the indentation trimmed by the marker" do
      expect_offense(<<~ERB)
        <div>
          <%- %><p>a</p>
          ^^^^^^ Remove the empty ERB tag.
        </div>
      ERB

      expect_correction(<<~ERB)
        <div>
        <p>a</p>
        </div>
      ERB
    end
  end

  context "when an empty ERB tag with a trim marker `<%-` follows HTML" do
    it "registers an offense and removes the tag only" do
      expect_offense(<<~ERB)
        <p>a</p><%- %>
                ^^^^^^ Remove the empty ERB tag.
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
      ERB
    end
  end

  context "when an empty ERB tag with a trim marker `-%>` is followed by HTML" do
    it "registers an offense and removes the tag only" do
      expect_offense(<<~ERB)
        <% -%><p>b</p>
        ^^^^^^ Remove the empty ERB tag.
      ERB

      expect_correction(<<~ERB)
        <p>b</p>
      ERB
    end
  end

  context "when an ERB tag has code" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <% foo %>
      ERB
    end
  end

  context "when an ERB tag has a comment only" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <% # note %>
      ERB
    end
  end

  context "when an ERB comment is empty" do
    it "registers an offense and removes the line" do
      expect_offense(<<~ERB)
        <p>a</p>
        <%# %>
        ^^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
        <p>b</p>
      ERB
    end
  end

  context "when an ERB comment with a trim marker `-%>` is empty" do
    it "registers an offense and removes the tag and the newline trimmed by the marker" do
      expect_offense(<<~ERB)
        <p>a</p><%# -%>
                ^^^^^^^ Remove the empty ERB tag.
        <p>b</p>
      ERB

      expect_correction(<<~ERB)
        <p>a</p><p>b</p>
      ERB
    end
  end

  context "when an ERB comment has text" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%# note %>
      ERB
    end
  end

  context "when a literal ERB tag (`<%%`) is empty" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%% %>
      ERB
    end
  end

  context "when an output tag is empty" do
    it "does not register an offense" do
      expect_no_offenses(<<~ERB)
        <%== %>
      ERB
    end
  end
end
