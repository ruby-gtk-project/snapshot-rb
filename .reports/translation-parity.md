# Translation parity — snapshot-rb vs. upstream (`origin/main`)

| | |
|---|---|
| Upstream | `main` @ `9d92e7c88f2cec448ae1e8d74207db4afa384702` |
| Port | `ruby` @ `81c790d` |
| Upstream catalogue keys | 102 (source-extracted `(msgctxt, msgid)` pairs) |
| Upstream languages | 56 (`po/LINGUAS`, 56 `po/*.po` files) |
| Port catalogue keys | **0** |
| Port languages | **0** |
| Gaps | 102 keys + 56 languages |

## Census

```sh
scripts/msgid-census.sh <upstream-tree> > upstream-msgids.tsv   # 5486 rows (includes every .po occurrence)
scripts/msgid-census.sh .                > port-msgids.tsv      # 0 rows
cut -f1,2 upstream-msgids.tsv | sort -u | wc -l   # 102 unique (msgctxt, msgid) keys
cut -f1,2 port-msgids.tsv      | sort -u | wc -l   # 0
```

56 `.po` files under `<upstream>/po/`, matching `po/LINGUAS` (56 lines).
Upstream's source alone (not counting `.po` re-occurrences) extracts to 102
distinct keys, pulled from `_()`/`gettext()` call sites in `src/`,
`<template translatable="yes">` attributes in the `.ui` files, and
`.desktop.in`/metainfo strings.

## The port's catalogue: zero

```sh
grep -rEn "(^|[^a-zA-Z0-9_])_\(['\"]" lib/ exe/   # no matches
grep -n gettext Gemfile snapshot-rb.gemspec        # no matches
find . -iname po -o -iname '*.po' -o -iname LINGUAS  # no matches
```

- **No gettext marker of any kind** (`_`, `N_`, `C_`, `NC_`, `ngettext`,
  `n_`, `s_`, `pgettext`, or the Ruby `gettext` gem's equivalents) appears
  anywhere in `lib/` or `exe/`. An earlier grep for `_(` during this audit
  matched `enum_(`/`capture_mode =` calls, not translation markers — once
  those false positives are excluded, the true count is 0.
- **No `gettext` dependency** in `Gemfile` or `snapshot-rb.gemspec`.
- **No `po/` directory, no `.po` file, no `LINGUAS` file, no `.pot`**
  anywhere in the port tree.
- Every user-visible string in the port — every button label, tooltip,
  dialog title, toast message, menu item, preferences row title — is a bare
  Ruby string literal: `'Previous Image'`, `'_Copy Picture'`,
  `'Could not take picture'`, etc. None of it is marked, so none of it is
  extractable, and even if it were byte-identical to upstream's English it
  would not connect to upstream's `.po` files, because nothing in the port
  calls `gettext` to do the lookup.

## Why this is total, not partial

Translation parity needs three things to hold, and all three are absent:

1. **Key sets equal** — upstream 102, port 0. Not close.
2. **Byte-identical msgids** — vacuously true of an empty set and
   meaningless: there is nothing to compare.
3. **Languages ship** — upstream's 56 `.po` files do not exist in the port
   at all, so even if every string were later marked and happened to match
   upstream's English byte-for-byte, none of the 56 donated translations
   would be reachable without separately importing the `.po` files and
   wiring a `.mo` build into the port (`rake`/`meson`), neither of which
   exists.

`translator_credits = 'translator-credits'` is set correctly in
`lib/about_dialog.rb:73` (the standard GNOME convention string gettext
replaces with real names once translated) — but with no `.po` files to
translate it, this will simply display the literal string
"translator-credits" forever, which is the About dialog visibly broken for
every non-English-reading tester, not a polish item.

## Verdict

**Zero translation parity.** The 56 languages upstream ships are entirely
unreachable from this port as it stands — not "English only for now" (not a
state this skill recognizes) but 102 missing keys and 56 missing catalogues,
full stop. This is the largest single gap found in this audit by any
measure (component count, test count, or translated-string count) and it
received no mention at all in `.reports/component-inventory.md` beyond a
one-line "out of scope for this survey" flag — see
`accountability-ensurance.md`.
