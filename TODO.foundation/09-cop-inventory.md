# 09 — Cop inventory

Card step 1's measured inventory. Produced by `Sirena::LintDebt`
(`lib/sirena/lint_debt.rb`), which re-runs rubocop against a config it
synthesises itself rather than one loaded from `.rubocop.yml` — so a
local `Exclude`, a deleted plugin, or a todo file renamed and
re-inherited under a new name cannot hide a suppressed offence from
this count. See that file's header comment for the mechanism.

Measured against `85acf20`, macOS 25.5.0 arm64, ruby 3.4.8 (rvm) and
independently reproduced on ruby 3.2.3 — both give the identical
**8877 / 286 files / 92 cops**. Reproduce with `bundle exec rake
lint:debt`.

## Total

**8877** suppressed offences, across **286** files, **92** cops,
**1542** distinct `(cop, file)` rows.

## The three suppression layers

Nesting the removals one at a time (a doubly-suppressed offence is
attributed to the layer removed **last** — the one whose removal makes
it visible; the total is exact regardless of the split):

| layer | config | offences | this layer hides |
|---|---|---|---|
| A | `.rubocop.yml` as committed | 0 | — |
| B | synthesis, but still inheriting `.rubocop_todo.yml` | 8858 | todo file: 8858 |
| C | full synthesis | 8873 | `.rubocop.yml`'s own keys: 15 |
| D | C plus `--ignore-disable-comments` | 8877 | inline directives: 4 |

`.rubocop.yml`'s own 15: `Style/RedundantArgument` (14 offences across
10 files — repo-wide, not a metrics cop) and `RSpec/SpecFilePathSuffix`
(1, `spec/benchmarks/flowchart_subgraph_benchmark.rb` — a directory
glob, not a single file). **Neither is eligible for the signed
exception allowlist** (`09-rubocop-todo-burndown.md:16-21` permits only
a metrics cop on a single grammar file) — they must be fixed, not
signed. `Sirena::LintDebt`'s allowlist refuses both automatically.

The 4 inline directives are all `Style/OneClassPerFile`:
`lib/sirena/theme.rb` (1, same-line `# rubocop:disable`),
`lib/tasks/generate_mermaid_fixtures.rake` (2, block directive),
`scripts/extract_mermaid_tests.rb` (1, block directive). Only the
same-line one in `theme.rb` moves under `NewCops: disable`-style
tooling that reads inline comments; the two block-directive files keep
their offences regardless, because the offending line falls between
the `disable`/`enable` pair either way.

## Debt by department

| department | offences | correctable |
|---|---|---|
| Style | 5615 | 5572 |
| Metrics | 1120 | 0 |
| RSpec | 955 | 10 |
| Layout | 689 | 521 |
| Lint | 324 | 302 |
| Naming | 160 | 0 |
| Performance | 13 | 13 |
| Gemspec | 1 | 1 |
| **total** | **8877** | **6419** |

`Style/StringLiterals` alone is **4499 offences = 50.7%** of all debt.

## Card step 1's classification — by cop, over all 92

`09-rubocop-todo-burndown.md:25-27` demands mechanical / RSpec /
metrics, split over **cops** (not offences — a split over offences
double-counts a cop with mixed correctability into two classes and
leaves `Layout/LineLength`, the repo's second-largest cop, without an
answer for burndown ordering).

Total function over cops:

1. department `RSpec` → **RSpec**
2. else department in `{Metrics, Naming}`, or any offence of that cop
   is not correctable → **metrics**
3. else → **mechanical**

Clause 2's second half is what makes the function total: a mixed
family (some offences autocorrectable, some not) goes to metrics,
because the non-correctable half needs human judgement and that is
what decides the burndown effort.

| class | cops | offences |
|---|---|---|
| mechanical | 69 | 6263 |
| RSpec | 10 | 955 |
| metrics | 13 | 1659 |
| **total** | **92** | **8877** |

Disjoint over cops (union = sum = 92) and complete over offences.
Burndown order (`09-rubocop-todo-burndown.md:27`, one family per PR):
**mechanical first** (largest, safest), RSpec second, metrics last.

### Mechanical (69 cops, 6263 offences)

Every cop's offences are all department Style/Layout/Lint/Performance/
Gemspec and fully autocorrectable. Largest first:

```
Style/StringLiterals                      4499
Style/TrailingCommaInHashLiteral           475
Style/TrailingCommaInArguments             296
Lint/AmbiguousOperatorPrecedence           269
Layout/TrailingEmptyLines                  163
Style/TrailingCommaInArrayLiteral          139
Layout/MultilineOperationIndentation        93
Style/NumericPredicate                      36
Layout/LineEndStringConcatenationIndentation 20
Layout/ArgumentAlignment                    16
Style/RedundantArgument                     14  (ineligible for signing, see above)
Style/RedundantRegexpArgument               13
Lint/UnusedMethodArgument                   12
Style/RedundantAssignment                   12
Layout/IndentationWidth                     11
Layout/EndAlignment                         11
Style/RedundantParentheses                  10
Layout/MultilineMethodCallIndentation        9
Style/StringConcatenation                    9
Layout/ExtraSpacing                          8
Style/HashEachMethods                        8
Performance/MapCompact                       8
Layout/EmptyLineAfterGuardClause             8
Style/SymbolArray                            7
Style/ClassAndModuleChildren                 6
Layout/HashAlignment                         6
Lint/UnusedBlockArgument                     6
Layout/ElseAlignment                         5
Layout/EmptyLinesAroundClassBody             5
Lint/AmbiguousRange                          5
Style/SafeNavigation                         5
Style/RescueStandardError                    5
Layout/SpaceAroundOperators                  5
Style/Semicolon                              4
Layout/FirstHashElementIndentation           4
Layout/HeredocIndentation                    4
Lint/UselessAssignment                       4
Style/IdenticalConditionalBranches           4
Layout/TrailingWhitespace                    4
Style/ConditionalAssignment                  3
Lint/RedundantDirGlobSort                    3
Style/SoleNestedConditional                  3
Style/MapIntoArray                           3
Style/MultipleComparison                     2
Style/MutableConstant                        2
Style/BlockDelimiters                        2
Performance/RedundantBlockCall               2
Style/NegatedIfElseCondition                 2
Lint/SymbolConversion                        2
Style/CombinableLoops                        2
Lint/UselessAccessModifier                   1
Performance/ConstantRegexp                   1
Style/SymbolProc                             1
Gemspec/RequireMFA                           1
Layout/SpaceAfterComma                       1
Performance/Squeeze                          1
Performance/RegexpMatch                      1
Style/CaseLikeIf                             1
Style/ExpandPathArguments                    1
Style/SuperArguments                         1
Style/RedundantLineContinuation              1
Style/HashSyntax                             1
Style/ComparableBetween                      1
Style/StringLiteralsInInterpolation          1
Layout/ArrayAlignment                        1
Style/MapToHash                              1
Style/SlicingWithRange                       1
Style/ZeroLengthPredicate                    1
Layout/EmptyLines                            1
```

### RSpec (10 cops, 955 offences)

```
RSpec/MultipleExpectations   462
RSpec/ExampleLength          414
RSpec/SpecFilePathFormat      53
RSpec/DescribeClass            8
RSpec/IncludeExamples           8
RSpec/MultipleDescribes         4
RSpec/BeEq                      2
RSpec/RepeatedExample            2
RSpec/SpecFilePathSuffix         1  (ineligible for signing, see above)
RSpec/PendingWithoutReason       1
```

### Metrics (13 cops, 1659 offences)

The 13 cops eligible for the signed exception allowlist, on a grammar
file, one at a time (`Sirena::LintDebt::METRICS_COPS`):

```
Metrics/MethodLength           441
Metrics/AbcSize                 365
Layout/LineLength               314
Naming/MethodParameterName      159
Metrics/CyclomaticComplexity    150
Metrics/PerceivedComplexity     121
Style/FormatStringToken          39
Metrics/BlockLength              35
Lint/DuplicateBranch             21
Metrics/ParameterLists            8
Style/OneClassPerFile              4  (all 4 are the ineligible inline directives above)
Lint/DuplicateMethods               1
Naming/PredicateMethod              1
```

`Layout/LineLength` sits here rather than in mechanical because 168 of
its 314 offences are not autocorrectable (line breaks need human
judgement) — 146 are.

## Four dead todo entries (free deletions, out of scope for this PR)

Confirmed by force-enabling each with `--only` against the
**synthesised** config (no local `Exclude` can suppress a hit under
`--only`, unlike testing against `.rubocop.yml` directly):

- `Gemspec/RequiredRubyVersion`
- `Layout/EmptyLineAfterMagicComment`
- `Performance/RedundantEqualityComparisonBlock`
- `Style/IfInsideElse`

Each gives **0** offences on the current tree. Card step 2 (deleting
cop families from `.rubocop_todo.yml`) is explicitly out of scope for
this PR; these four are the cheapest first deletions when that item
starts.

## What this inventory does not cover

- **The inherited Ribose config hides further debt of its own.** It
  disables 89 cops; re-enabling all of them (independent of anything
  `.rubocop_todo.yml` or `.rubocop.yml` does — this is entirely inside
  the pinned remote) gives **9587** offences, **+710** across 21 cops:
  `Style/AsciiComments` 279, `Style/InlineComment` 106,
  `Metrics/ClassLength` 71, `Style/IfUnlessModifier` 67,
  `Style/CollectionMethods` 63, `Style/WordArray` 30, and 15 more.
  Defensible as an org-wide baseline, but undeclared until now. The
  remote is SHA-pinned (`03e81f3124ceab971146671d140e410e0e915c06`);
  bumping it to move debt off the board would be a deliberate,
  separate change.
- Does not pin `rubocop-ast`, `parser` or `prism` — `Gemfile.lock` is
  gitignored (`.gitignore:44`), so a transitive bump can move the
  total without anyone touching `.rubocop.yml`.
- Counts offences, not risk. A cop with one offence and a cop with
  4499 count equally toward "92 cops covered".
