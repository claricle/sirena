# 21 — class and ER label text

Can start: now. Nothing blocks it; it needs only the survey in
`docs/label-text-baseline.md`, which runs on `main`.
Blocks: 14's Done. Item 14's hard gate includes the `label-text` rule, and
this item removes the failures that rule reports for class and ER.

Raised from the label-text baseline. `label-text` is part of 14's hard gate
from the first day, so these cases are fixed here and not waived.

## Facts

Measured on `main` at `30a74ebe` (`docs/label-text-baseline.md`, cohort cases
only):

| Type | Cohort | `label-text` failures |
|---|---|---|
| class | 142 | 73 |
| er | 6 | 3 |

Sirena draws text that differs from the reference's. The class
failures include these shapes:

- Member text: the reference draws `test`, Sirena draws `+ test`
  (`class/033_platform_yari_class_32`); the reference draws `+String beakColor`,
  Sirena draws `+ beakColor: String` (`class/031_platform_yari_class_30`).
- Annotation: the reference draws `«interface»`, Sirena draws `<<interface>>`
  (13 cases, `class/034_platform_yari_class_33`).
- Class-name generics: the reference draws `Car<T>`, Sirena draws `Car~T~`
  (7 cases, `class/108_parser_should_handle_generic_class_107`).

ER attribute rows read type then name in the reference and name then type in
Sirena: `string registrationNumber` against `registrationNumber string`
(3 cases, `er/002_platform_yari2_er_1`). The ER cells are merged per row by the
extractor rule in item 14 section 5, so this is a text difference and not a
count difference.

## Scope

Make Sirena draw the reference's text for class members, class annotations,
class-name generics and ER attribute rows. There is no waiver: a difference
the owner decides to keep is a change to item 14's `label-text` rule, made in
item 14, and until then it is a failure.

Out of scope: class cardinality terminals and namespace-qualified class ids
(the baseline does not count them), and every geometry change. Item 07 burns
down the class corpus and item 06 the ER corpus, each by its own measure; a fix
there that removes one of these cases counts here too. The other 52 failing
cases (flowchart 43, sequence 6, architecture 2, requirement 1) have no item
yet, and 14's gate needs them at zero as well.

## Done when

- Re-running the baseline's Reproduce block reports 0 `label-text` failures
  for class and er. Once item 14's comparator exists, the comparator reports
  the same.
- A spec per shape above asserts the drawn text against the reference text,
  and goes red when the fix is reverted.

## Files

`lib/sirena/renderer/class_diagram.rb`, `lib/sirena/renderer/er_diagram.rb`,
and the matching specs. Start there; if the rewrite happens in the parser or
the layout, that file changes instead.
