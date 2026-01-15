# frozen_string_literal: true

require "spec_helper"

require "prism"

RSpec.describe RuboCop::Herb::Converter do
  shared_examples "a Ruby code extractor for ERB" do
    it "collects Ruby parts from ERB" do
      expect(subject).to eq(expected)
    end

    it "preserves byte lengths" do
      expect(subject.bytesize).to eq(source.bytesize)
    end

    it "generates valid Ruby code" do
      parse_result = Prism.parse(subject)
      expect(parse_result.errors).to be_empty
    end
  end

  describe "#convert" do
    subject { described_class.new.convert(source) }

    describe "with a content ERB tag" do
      let(:source) { "<div><%= user.name %></div>" }
      let(:expected) { "         user.name;        " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag" do
      let(:source) { "<div><%# user.name %></div>" }
      let(:expected) { "       # user.name         " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with if-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% if admin? %>",
         "    Hello, Admin!",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     if admin?;  ",
         "                 ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with multiple ERB nodes on single line" do
      let(:source) { "<% if user %><%= user.name %><% end %>" }
      let(:expected) { "   if user;      user.name;     end;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag on its own line" do
      let(:source) do
        ["<%# comment %>",
         "<% if :cond %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["  # comment   ",
         "   if :cond;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag followed by other ERB on the same line" do
      let(:source) do
        ["<%# comment %><% if :cond %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["                 if :cond;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag on its own lines" do
      let(:source) do
        ["<%#",
         "  multiline",
         "  comment",
         "%>",
         "<% if :cond %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "# multiline",
         "# comment",
         "  ",
         "   if :cond;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag with sufficient indentation" do
      let(:source) do
        ["<%#",
         "    multiline",
         "    comment",
         "%>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "  # multiline",
         "  # comment",
         "  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an indented multiline comment ERB tag" do
      let(:source) do
        ["<div>",
         "  <%#",
         "      multiline",
         "      comment",
         "  %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "    #",
         "    # multiline",
         "    # comment",
         "#   ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag followed by other ERB on the same line" do
      let(:source) do
        ["<%#",
         "  multiline",
         "  comment",
         "%><% if :cond %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["   ",
         "           ",
         "         ",
         "     if :cond;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag without leading whitespace" do
      let(:source) do
        ["<%#",
         "text",
         "more",
         "%>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "#ext",
         "#ore",
         "  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag with tab indentation" do
      let(:source) do
        ["<%#",
         "\ttext",
         "\tmore",
         "%>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "#text",
         "#more",
         "  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag with multibyte characters" do
      let(:source) do
        ["<%#",
         "日本語",
         "%>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "#  本語",
         "  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end
  end
end
