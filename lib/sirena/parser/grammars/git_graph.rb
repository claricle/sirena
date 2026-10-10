# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Git Graph diagrams
      class GitGraph < Common
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe.as(:statements) >>
            ws?
        end

        rule(:header) do
          str("gitGraph") >>
            ((space? >> direction >> space? >> str(":")) | str(":")).maybe >>
            ws?
        end

        rule(:direction) do
          (str("TB") | str("LR") | str("BT")).as(:direction)
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          commit_stmt |
            branch_stmt |
            checkout_stmt |
            switch_stmt |
            merge_stmt |
            cherry_pick_stmt |
            acc_title_stmt |
            acc_descr_stmt
        end

        rule(:acc_title_stmt) do
          str("accTitle") >> space? >> colon >> space? >>
            (line_end.absent? >> any).repeat.as(:acc_title) >>
            line_end
        end

        rule(:acc_descr_stmt) do
          acc_descr_single_line | acc_descr_multi_line
        end

        rule(:acc_descr_single_line) do
          str("accDescr") >> space? >> colon >> space? >>
            (line_end.absent? >> any).repeat.as(:acc_descr) >>
            line_end
        end

        rule(:acc_descr_multi_line) do
          str("accDescr") >> whitespace? >> lbrace >> ws? >>
            (rbrace.absent? >> any).repeat.as(:acc_descr) >>
            rbrace >> line_end
        end

        rule(:commit_stmt) do
          (
            str("commit") >>
            commit_options.maybe.as(:options)
          ).as(:commit) >>
            line_end
        end

        # A quoted message may follow `commit` directly: `commit"msg"`.
        rule(:commit_options) do
          (space.repeat(1) | (str('"') | str("'")).present?) >>
            (commit_option >> space?).repeat(1)
        end

        rule(:commit_option) do
          commit_id | commit_type | commit_tag | commit_message
        end

        # `commit "msg"` and `commit msg: "msg"` both set the message.
        rule(:commit_message) do
          (str("msg:") >> space? >> quoted_text(:message)) |
            quoted_text(:message)
        end

        rule(:commit_id) do
          str("id:") >> space? >>
            ((str('"') >> match('[^"]').repeat(1).as(:id) >> str('"')) |
             (str("'") >> match("[^']").repeat(1).as(:id) >> str("'")) |
             match('[^\s,]').repeat(1).as(:id))
        end

        rule(:commit_type) do
          str("type:") >> space? >>
            (str("NORMAL") | str("REVERSE") | str("HIGHLIGHT")).as(:type)
        end

        rule(:commit_tag) do
          str("tag:") >> space? >>
            ((str('"') >> match('[^"]').repeat(1).as(:tag) >> str('"')) |
             (str("'") >> match("[^']").repeat(1).as(:tag) >> str("'")) |
             match('[^\s,]').repeat(1).as(:tag))
        end

        rule(:branch_stmt) do
          (
            str("branch") >>
            branch_ref(:name) >>
            branch_options.maybe.as(:options)
          ).as(:branch) >>
            line_end
        end

        # mermaid accepts git's own branch-name characters, not just an
        # identifier — `release/1.0.0` is a real branch name a source can
        # check out. A word char first, a word char or hyphen last, so
        # `.foo`, `/foo`, `foo.`, `foo/` are all rejected; do not replace
        # this with `match('[...]').repeat`, which cannot express that
        # boundary. Use `TrimmedRun`, not a plain `GreedyRun`, for the
        # tail: see `atoms/trimmed_run.rb`.
        rule(:branch_name) do
          match['\w'] >> TrimmedRun.new('[-.\/\w]', '[.\/]')
        end

        # The branch operand of a statement, with the whitespace after its
        # keyword. A quoted name allows spaces and any other character but the
        # closing quote, and may follow the keyword directly (`branch"a b"`);
        # a bare name needs at least one space. Not a `rule`: the capture name
        # differs per statement.
        def branch_ref(key)
          (space? >> quoted_text(key)) |
            (space.repeat(1) >> branch_name.as(key))
        end

        # A backslash escapes the character after it, except a line break, so
        # `"a\\"` is a complete string; State.unquote resolves the escapes
        # afterwards. An unescaped line break is part of the string.
        def quoted_text(key)
          quoted_by('"', key) | quoted_by("'", key)
        end

        def quoted_by(quote, key)
          body = quoted_escape | match("[^#{quote}\\\\]")

          str(quote) >> body.repeat.as(key) >> str(quote)
        end

        rule(:quoted_escape) { str("\\") >> match('[^\n\r\u2028\u2029]') }

        rule(:branch_options) do
          space >> (branch_option >> space?).repeat(1)
        end

        rule(:branch_option) do
          str("order:") >> space? >> match("[0-9]").repeat(1).as(:order)
        end

        rule(:checkout_stmt) do
          (
            str("checkout") >>
            branch_ref(:branch)
          ).as(:checkout) >>
            line_end
        end

        rule(:switch_stmt) do
          (
            str("switch") >>
            branch_ref(:branch)
          ).as(:switch) >>
            line_end
        end

        rule(:merge_stmt) do
          str("merge") >>
            (
              branch_ref(:branch) >>
              merge_options.maybe.as(:options)
            ).as(:merge) >>
            line_end
        end

        rule(:merge_options) do
          space >> (merge_option >> space?).repeat(1)
        end

        rule(:merge_option) do
          commit_id | commit_type | commit_tag |
            (str("random:") >> quoted_string)
        end

        rule(:cherry_pick_stmt) do
          (
            str("cherry-pick") >> space >>
            cherry_pick_options.as(:options)
          ).as(:cherry_pick) >>
            line_end
        end

        rule(:cherry_pick_options) do
          (cherry_pick_option >> space?).repeat(1)
        end

        rule(:cherry_pick_option) do
          cherry_pick_id | cherry_pick_parent | commit_tag
        end

        rule(:cherry_pick_id) do
          str("id:") >> space? >>
            ((str('"') >> match('[^"]').repeat(1).as(:id) >> str('"')) |
             (str("'") >> match("[^']").repeat(1).as(:id) >> str("'")) |
             match('[^\s,]').repeat(1).as(:id))
        end

        rule(:cherry_pick_parent) do
          str("parent:") >> space? >>
            ((str('"') >> match('[^"]').repeat(1).as(:parent) >> str('"')) |
             (str("'") >> match("[^']").repeat(1).as(:parent) >> str("'")) |
             match('[^\s,]').repeat(1).as(:parent))
        end

        rule(:quoted_string) do
          (str('"') >> match('[^"]').repeat(0) >> str('"')) |
            (str("'") >> match("[^']").repeat(0) >> str("'"))
        end

        root(:diagram)
      end
    end
  end
end
