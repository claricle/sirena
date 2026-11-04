# frozen_string_literal: true

require "spec_helper"
require_relative "salt_helpers"

RSpec.describe Sirena::Notation::PlantUMLSalt::Parser do
  include SaltHelpers

  let(:source) { File.read(File.join(SaltHelpers::FIXTURES, "01.salt")) }
  let(:table) do
    parse_salt(source).rows.first.cells.first.rows.first.cells.first
  end

  describe "the first corpus block" do
    it "nests the window block around one T! table" do
      expect(table.modifier).to eq("T!")
    end

    it "reads the rows' depth from their leading + marks" do
      expect(table.rows.map(&:depth)).to eq([1, 2, 3, 3])
    end

    it "splits each row into three cells" do
      expect(table.rows.map { |row| row.cells.size }).to eq([3, 3, 3, 3])
    end

    it "keeps the bold run and the attribute text as separate runs" do
      first = table.rows.first.cells.first
      expect(first.runs.map { |r| [r.text, r.bold] })
        .to eq([["Figure", true], [' alt="PDF icon"', false]])
    end

    it "reads . as an empty cell" do
      expect(table.rows.first.cells[1].kind).to eq(:empty)
    end

    it "reads a quoted cell as a text field without its quotes" do
      field = table.rows.last.cells.last
      expect([field.kind, field.text]).to eq([:field, "relevant content"])
    end

    it "treats the table as gridded" do
      expect(table).to be_grid
    end
  end

  describe "widgets" do
    let(:source) do
      "@startsalt\n{\n[OK] | [X] | [] | () | (X) done | ^pick^b^ | " \
        "<i>it</i><u>u</u><s>s</s><color:red>r</color>\n}\n@endsalt"
    end
    let(:cells) { widgets(parse_salt(source).rows.first.cells.first) }

    it "reads each widget kind" do
      expect(cells.map(&:kind))
        .to eq(%i[button checkbox checkbox radio radio droplist text])
    end

    it "reads ticked state" do
      expect(cells.map(&:checked)).to eq([false, true, false, false, true,
                                          false, false])
    end

    it "reads droplist's first item as its label" do
      expect(cells[5].text).to eq("pick")
    end

    it "reads italic, underline, strike and colour runs" do
      runs = cells.last.runs
      expect(runs.map { |r| [r.italic, r.underline, r.strike, r.color] })
        .to eq([[true, false, false, nil], [false, true, false, nil],
                [false, false, true, nil], [false, false, false, "red"]])
    end
  end

  describe "unrecognised input" do
    it "keeps an unknown tag as literal text" do
      cell = widgets(parse_salt("@startsalt\n{\n<P> | <Div>\n}\n@endsalt")
                       .rows.first.cells.first)
      expect(cell.map(&:text)).to eq(["<P>", "<Div>"])
    end

    it "does not raise on unbalanced braces or no braces" do
      ["@startsalt\n}\n}\nhi\n", "@startsalt\n{ {\n a\n", "",
       "\xFF\xFE{"].each do |bad|
        expect { parse_salt(bad) }.not_to raise_error
      end
    end
  end
end
