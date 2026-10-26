# GRDB — Full-Text Search

Use **FTS5** — better ranking, prefix indexes, custom tokenizers. FTS3/FTS4
exist (`using: FTS3()` / `FTS4()`) but only reach for them on ancient SQLite;
default to FTS5. FTS tables are SQLite *virtual tables* created in a migration.

## Creating an FTS5 table

```swift
migrator.registerMigration("fts") { db in
    try db.create(virtualTable: "series_ft", using: FTS5()) { t in
        t.tokenizer = .unicode61()      // default; set before columns
        t.column("title")
        t.column("altTitles")
        t.prefixes = [2, 4]             // prefix indexes for autocomplete
    }
}
```

- FTS columns are untyped text; no constraints, no `.text`/`.notNull`.
- `t.prefixes = [2,4]` builds prefix indexes so `matchingAllPrefixesIn` /
  `"ter*"` autocomplete stays fast.

## External content (don't duplicate the text)

The important pattern for a real app: keep the real row in a normal table, let
FTS index it without storing a second copy.

```swift
// the source-of-truth table
try db.create(table: "series") { t in
    t.primaryKey("id", .integer)
    t.column("title", .text).notNull()
    t.column("altTitles", .text)
}

// content-synced: GRDB generates INSERT/UPDATE/DELETE triggers keeping
// series_ft in sync with series (matched by rowid). columns must match.
try db.create(virtualTable: "series_ft", using: FTS5()) { t in
    t.synchronize(withTable: "series")
    t.column("title")
    t.column("altTitles")
}
```

- `synchronize(withTable:)` also back-fills the index from existing rows.
- Dropping the FTS table? Also drop its triggers:
  `try db.drop(table: "series_ft"); try db.dropFTS5SynchronizationTriggers(forTable: "series_ft")`.
- **Contentless** (`t.content = ""`): index only, no stored columns. Saves
  space but you CANNOT read column values back from it — fetch content from the
  real table via the join. Synchronization triggers are your responsibility.

## Building patterns safely

`FTS5Pattern` initializers are **failable** — they return `nil` on empty or
untokenizable input. Never force-unwrap user text; guard and fall back.

```swift
let query = searchField                       // untrusted user text
guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else {
    return []                                 // empty/garbage query → no FTS
}
```

| Builder | Matches |
|---|---|
| `FTS5Pattern(matchingAnyTokenIn:)` | any token (OR) |
| `FTS5Pattern(matchingAllTokensIn:)` | all tokens (AND) — the usual default |
| `FTS5Pattern(matchingAllPrefixesIn:)` | token prefixes (autocomplete) |
| `FTS5Pattern(matchingPhrase:)` | exact adjacent phrase |
| `FTS5Pattern(matchingPrefixPhrase:)` | phrase at start |

Raw FTS5 syntax (`AND`/`OR`/`NEAR`/`*`) — validates against the table, THROWS
on bad syntax or unknown column:

```swift
let pattern = try db.makeFTS5Pattern(rawPattern: "berserk OR kentaro", forTable: "series_ft")
```

## Querying

```swift
// whole-table match via query interface
let hits = try Series_ft.matching(pattern).fetchAll(db)

// column-scoped match
try Series_ft.filter { $0.title.match(pattern) }.fetchAll(db)

// external content: join FTS rowid back to the real table
let series = try Series.fetchAll(db, sql: """
    SELECT series.* FROM series
    JOIN series_ft ON series_ft.rowid = series.id
    WHERE series_ft MATCH ?
    """, arguments: [pattern])
```

`matching(pattern)` extends the WHERE (AND) like `filter`. `pattern` binds as a
statement argument — never string-interpolate it into SQL.

## Ranking / relevance

FTS5 exposes a hidden `rank` column (negative bm25; ascending = best first).

```swift
try Series_ft.matching(pattern).order(Column("rank")).fetchAll(db)

// weighted per-column bm25 (raw SQL): weight title over altTitles
try Series.fetchAll(db, sql: """
    SELECT series.* FROM series
    JOIN series_ft ON series_ft.rowid = series.id
    WHERE series_ft MATCH ? ORDER BY bm25(series_ft, 10.0, 1.0)
    """, arguments: [pattern])
```

## Tokenizers

Set `t.tokenizer` at table creation. Changing it later needs a rebuild (below).

```swift
t.tokenizer = .unicode61()                          // default: case-fold, strip diacritics
t.tokenizer = .unicode61(diacritics: .keep)         // keep accents
t.tokenizer = .unicode61(tokenCharacters: ["#", "_"], // treat these as in-word
                         separators: ["-"])
t.tokenizer = .ascii()                              // ASCII-only case folding
t.tokenizer = .porter()                             // english stemming (wraps unicode61)
t.tokenizer = .porter(.unicode61(diacritics: .keep))
```

- `unicode61` (default) fits most title search: diacritic-insensitive, unicode
  word boundaries. `porter` stems (`readers`→`reader`) — good for prose bodies,
  usually overkill for titles. `ascii` only for pure-ASCII data.

### Rebuild after a tokenizer change

Changing the tokenizer doesn't re-tokenize existing rows. Rebuild the index:

```swift
try db.execute(sql: "INSERT INTO series_ft(series_ft) VALUES('rebuild')")
```

### Custom tokenizer (rare)

Reach for `FTS5WrapperTokenizer` only for synonyms, custom normalization, or
non-english stemming — wrap a real tokenizer and post-process its tokens.

```swift
final class SynonymTokenizer: FTS5WrapperTokenizer {
    static let name = "synonym"
    let wrappedTokenizer: any FTS5Tokenizer
    init(db: Database, arguments: [String]) throws {
        wrappedTokenizer = try db.makeTokenizer(.unicode61())
    }
    func accept(token: String, flags: FTS5TokenFlags,
                for tokenization: FTS5Tokenization,
                tokenCallback: FTS5WrapperTokenCallback) throws {
        try tokenCallback(token, flags)                 // emit again w/ .colocated for synonyms
    }
}
// register once: config.prepareDatabase { db in db.add(tokenizer: SynonymTokenizer.self) }
// use: t.tokenizer = SynonymTokenizer.tokenizerDescriptor()
```

## Gotchas

- `FTS5Pattern(...)` is nil on empty/garbage input — guard, don't `!`.
- `makeFTS5Pattern(rawPattern:)` throws — wrap in `try`, handle bad user syntax.
- Contentless tables can't return column content — always join to the real
  table for display data.
- Content and query text must share unicode normalization; normalize untrusted
  input (`str.precomposedStringWithCanonicalMapping`) if matches go missing.
- FTS columns are untyped — no `.notNull()`/`.text`, and no foreign keys.
