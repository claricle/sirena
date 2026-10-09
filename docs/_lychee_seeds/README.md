# lychee seed fixtures

These deliberately broken pages prove that `docs/lychee.toml` rejects the
four failure classes required by the docs-site plan. Jekyll excludes this
underscore-prefixed directory, so none of these fixtures reaches `_site` or
the published documentation.

The link workflow checks each fixture independently, requires every check to
fail, and verifies that the two HTTP fixtures report their intended status.
That last assertion prevents a DNS or connection failure from impersonating
the 403/429 proof.

- `broken-relative-link.html` points to an absent relative page.
- `broken-fragment.html` points to an absent fragment on itself.
- `seeded-403.html` points to an endpoint that responds with HTTP 403.
- `seeded-429.html` points to an endpoint that responds with HTTP 429.
