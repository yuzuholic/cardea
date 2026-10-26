# Records

Records are plain value types extended with database protocols. No uniquing,
no auto-update, no lazy-loading — by design.

## The three protocols

| Protocol | Grants | Requirement |
|---|---|---|
| `FetchableRecord` | `fetchOne/All/Set/Cursor` from SQL and requests | `init(row:)` — derived from `Decodable` |
| `TableRecord` | query interface (`filter`, `order`, …), batch ops, key lookups | `databaseTableName` (defaulted from type name: `Place` → `place`, `HTTPRequest` → `httpRequest`) |
| `PersistableRecord` / `MutablePersistableRecord` | `insert/update/save/upsert/delete` | `encode(to:)` — derived from `Encodable` |

Choosing the persistable flavor:
- **struct + auto-incremented PK** → `MutablePersistableRecord` + implement
  `mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }`
- **class** → `PersistableRecord` (+ `didInsert` if auto-incremented PK)
- **struct with natural key** (slug, uuid, provider id) → `PersistableRecord`,
  ignore `didInsert`
- The legacy `Record` base class is not recommended since GRDB 7.

## Canonical Codable record

```swift
struct Player: Codable, Identifiable, Sendable {
    var id: Int64?          // Optional for auto-increment; see Identifiable note
    var name: String
    var score: Int
}

extension Player: FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let score = Column(CodingKeys.score)
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

Columns-from-CodingKeys is the canonical pattern: renames propagate into both
the DSL and (via interpolation) raw SQL.

Non-Codable variant: implement `init(row:)` reading `row[Columns.x]` and
`encode(to container: inout PersistenceContainer)` assigning
`container[Columns.x] = x`. Useful when properties don't map 1:1 to columns
(e.g. two columns folded into `CLLocationCoordinate2D`).

Performance variant: lock column order with
`static var databaseSelection: [any SQLSelectable]` and decode by numeric
index in `init(row:)` (`id = row[0]`). Only when profiling demands it.
**Gotcha:** `databaseSelection` MUST be explicitly typed
`[any SQLSelectable]` or the compiler silently misses the requirement and you
keep getting `SELECT *`.

## Persistence methods

```swift
try place.insert(db)
let p2 = try place.inserted(db)      // non-mutating (use in Sendable closures)
try place.update(db)                  // throws RecordError.recordNotFound if no row
try place.update(db, columns: ["title"])
try place.updateChanges(db) { $0.isFavorite = true } // no-op if unchanged
try place.save(db)                    // UPDATE, then INSERT if nothing updated
try place.upsert(db)
try place.delete(db)                  // -> Bool (row existed?)
try place.exists(db)
```

Batch (on `TableRecord`, also on `Table("name")`):

```swift
try Player.updateAll(db) { [$0.score.set(to: 0), $0.bonus.set(to: nil)] }
try Player.filter { $0.team == "red" }.updateAll(db) { $0.score += 1 }
try Player.deleteAll(db, ids: [1, 2, 3])
try Player.deleteOne(db, id: 1)
try Player.deleteOne(db, key: ["email": "a@b.com"])
```

`updateAll` returns updated-row count; `deleteAll` deleted count. A specific
conflict policy can be passed: `updateAll(db, onConflict: .ignore) { ... }`.

## Upsert (SQLite 3.35+ / iOS 15+)

```swift
try player.upsert(db)   // conflict on any uniqueness constraint -> overwrite all but PK
```

Fine control with `upsertAndFetch`:

```swift
let upserted = try vocabulary.upsertAndFetch(
    db, onConflict: ["word"],                 // conflict target
    doUpdate: { excluded in
        [Column("count") += 1,                 // computed on conflict
         Column("isTainted").noOverwrite]      // keep existing value
    })
// `excluded` refers to the values that triggered the conflict:
// [Column("date").set(to: max(Column("date"), excluded["date"]))]
```

Upsert fires insert callbacks (`didInsert` reports the affected rowid);
update callbacks are NOT called.

## RETURNING — the `*AndFetch` family

`insertAndFetch`, `saveAndFetch`, `updateAndFetch`, `upsertAndFetch`,
`updateChangesAndFetch`, plus request-level `deleteAndFetchAll` /
`updateAndFetchAll`. Use to read defaults/generated columns in one round trip,
or to insert a partial record and get the full row back:

```swift
struct PartialPlayer: Encodable, PersistableRecord {
    static let databaseTableName = "player"
    var name: String
}
let player = try PartialPlayer(name: "Alice").insertAndFetch(db, as: Player.self)
```

Check SQLite's documented RETURNING caveats before using the batch variants.

## Persistence callbacks

Order: `willSave → aroundSave → willInsert/willUpdate → aroundInsert/aroundUpdate
→ didInsert/didUpdate → didSave`; deletes: `willDelete → aroundDelete → didDelete`.

- Validation belongs in `willSave` (throw to abort).
- Callbacks fire only on instance methods — NOT on batch ops or raw SQL.
- In a `did***` callback the transaction may not be committed yet. For
  post-commit side effects (deleting files, notifications):

```swift
func willDelete(_ db: Database) {
    db.afterNextTransaction { _ in try? deleteFileOnDisk() }
}
```

## Identifiable

Conforming unlocks type-safe APIs: `find(db, id:)`, `fetchOne(db, id:)`,
`fetchAll(db, ids:)`, `filter(id:)`, `deleteAll(db, ids:)`, `selectID()`,
`exists(db, id:)`.

**Do NOT declare `Identifiable` when the PK is auto-incremented and `id` is
`Int64?`** — an optional id is not a stable identity (GRDB issue #1435).
For non-"id" single-column PKs, forward: `var id: String { isoCode }`.

Non-Identifiable types use the untyped `key:`/`keys:` variants, which also
accept composite keys: `fetchOne(db, key: ["citizenId": 1, "countryCode": "FR"])`.
Tables without an explicit PK are addressed by hidden `rowid`.

## Record comparison

```swift
try newPlayer.updateChanges(db, from: oldPlayer)   // diff-only UPDATE, Bool result
newPlayer.databaseEquals(oldPlayer)                // same DB representation?
try newPlayer.databaseChanges(from: oldPlayer)     // [String: DatabaseValue] diffs
```

Comparison uses the database encoding — no `Equatable` needed. For syncing a
table against a payload, see groue/SortedDifference.

## Conflict resolution (INSERT OR REPLACE etc.)

Policies: abort (default), replace, rollback, fail, ignore. Set per-type:

```swift
static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)
```

or per-table-definition: `t.column("email", .text).unique(onConflict: .replace)`.
Notes: with `.ignore`, a failed insert still calls `didInsert` with a garbage
rowid — detect real outcomes with `insertAndFetch` + catch
`RecordError.recordNotFound`. `.replace` may delete rows invisibly to
transaction observers.

## Beyond FetchableRecord

Polymorphic row decoding or context-dependent decoding don't fit
`FetchableRecord` — decode `Row`s manually instead of fighting the protocol.
