---
type: Pattern
title: "Multiline String Literals"
description: "Use GHC 9.12 MultilineStrings for readable indentation-aware embedded text"
timestamp: 2026-07-24T09:56:04-07:00
resource: mori://shinzui/haskell-jitsurei/docs/core-multiline-strings
tags: [core, haskell, ghc-9.12, multiline-strings, text]
status: current
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: 2026-07-24T09:56:04-07:00
    document_timestamp: 2026-07-24T09:56:04-07:00
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-fable-5
---

# Multiline String Literals

Use the `MultilineStrings` extension (GHC 9.12+) to write readable multi-line strings with automatic indentation stripping.

## Motivation

Constructing multi-line strings in Haskell is verbose. The typical approaches — `unlines` with a list of strings, string gaps, or quasiquoters — are either noisy or require Template Haskell. `MultilineStrings` provides native syntax that keeps string content aligned with surrounding code.

```haskell
-- Before: unlines + list
sql :: String
sql = unlines
  [ "SELECT m.id, m.status"
  , "FROM members m"
  , "WHERE m.active = true"
  , "ORDER BY m.created_at"
  ]

-- After: MultilineStrings
sql :: String
sql = """
  SELECT m.id, m.status
  FROM members m
  WHERE m.active = true
  ORDER BY m.created_at
  """
```

## Enabling the Extension

```haskell
{-# LANGUAGE MultilineStrings #-}
```

Or in Cabal:

```haskell
common common
  default-language: GHC2024
  default-extensions:
    MultilineStrings
```

## Basic Usage

A multiline string is delimited by `"""`. The content between the delimiters is post-processed to strip common indentation:

```haskell
{-# LANGUAGE MultilineStrings #-}

greeting :: String
greeting = """
  Hello,
  World!
  """
-- equivalent to "Hello,\nWorld!"
```

The indentation shared by all non-empty lines (relative to the leftmost content) is stripped, and leading/trailing newlines are removed.

## Post-Processing Algorithm

GHC applies seven steps between string gap collapsing and escape character resolution:

1. **Split by newlines** — split the raw content by `\r\n`, `\r`, `\n`, or `\f`
2. **Expand leading tabs** — replace leading tabs with spaces to the next tab stop (8-character intervals, per Haskell 2010 Report §10.3)
3. **Compute common prefix** — find the longest whitespace prefix shared by all lines, excluding the first line and whitespace-only lines
4. **Strip common prefix** — remove the prefix from each line; whitespace-only lines become empty
5. **Rejoin with `\n`** — recombine lines using `\n` regardless of original line endings
6. **Remove leading `\n`** — strip exactly one leading newline if present
7. **Remove trailing `\n`** — strip exactly one trailing newline if present

## Examples

### Indentation Stripping

The baseline is the longest whitespace prefix shared by the *content* lines. The
first line and whitespace-only lines — including the line holding the closing
`"""` — are excluded from the computation, so the closing delimiter's column does
**not** set the baseline (aligning it with the content is a readability
convention, nothing more):

```haskell
html :: String
html = """
  <div>
    <p>Hello</p>
  </div>
  """
-- equivalent to "<div>\n  <p>Hello</p>\n</div>"
```

Two spaces are common to all content lines, so they are stripped. The `<p>` line retains its extra two spaces of nesting.

### Content on the Opening Line

Characters on the same line as the opening `"""` are preserved and do not participate in common prefix calculation:

```haskell
s :: String
s = """Line 1
  Line 2
  """
-- equivalent to "Line 1\nLine 2"
```

### Preserving a Trailing Newline

Since the final newline is stripped, add a blank line before the closing delimiter to keep it:

```haskell
withTrailingNewline :: String
withTrailingNewline = """
  line 1
  line 2

  """
-- equivalent to "line 1\nline 2\n"
```

### Suppressing a Trailing Newline with String Gaps

Use a string gap (`\` ... `\`) to suppress the trailing newline without an extra blank line:

```haskell
noTrailingNewline :: String
noTrailingNewline = """
  line 1
  line 2\
  \"""
-- equivalent to "line 1\nline 2"
```

### Blank Lines in Content

Whitespace-only lines are excluded from the common prefix calculation and become empty in the output:

```haskell
spaced :: String
spaced = """
  abc

  def
  """
-- equivalent to "abc\n\ndef"
```

### Quoting

Double quotes do not need escaping unless they form a triple-quote sequence:

```haskell
jsonExample :: String
jsonExample = """
  {"name": "Alice", "age": 30}
  """
-- equivalent to "{\"name\": \"Alice\", \"age\": 30}"
-- (No escaping needed in the source!)
```

## OverloadedStrings

After post-processing, multiline strings are indistinguishable from regular string literals in the AST. They work transparently with `OverloadedStrings`:

```haskell
{-# LANGUAGE MultilineStrings #-}
{-# LANGUAGE OverloadedStrings #-}

import Data.Text (Text)

query :: Text
query = """
  SELECT id, name
  FROM users
  WHERE active = true
  """
```

## When to Use

- SQL queries, HTML/JSON templates, or any multi-line text embedded in source
- Strings containing double quotes (avoids escape noise)
- Anywhere readability benefits from preserving the visual shape of the content

## When NOT to Use

- Single-line strings — regular `"..."` is simpler
- Strings that need interpolation — consider a quasiquoter instead (`[i|...|]`, `[sql|...|]`)
- Content where leading/trailing whitespace control is critical and the stripping rules would be surprising
