# `series.sqlite` field guide

One table, `series`. 557,313 rows × 146 columns. All statistics below were
measured against the live database; percentages marked *(active)* are over the
302,894 rows with `state = 'active'`.

```
data/series.sqlite   3.2 GB   (decompressed from series.sqlite.zst, 352 MB)
```

`data/` is gitignored. Rebuild with `python scripts/decompress_db.py` if absent.

---

## The `state` column — read first

| value | rows | meaning |
|---|---|---|
| `active` | 302,894 | canonical titles — **the only rows you should model on** |
| `merged` | 254,416 | alternate editions/duplicates, folded into `merged_with` |
| `deleted` | 3 | tombstones |

`merged_with` holds the id of the surviving row (as TEXT, not INTEGER — cast it).
Examples: `One Piece (Official Colored)` → `377`, `Land of the Lustrous` → `616`.

Modelling on unfiltered rows produces similarity matrices dominated by
near-identical duplicate documents and inflates every coverage figure by ~84%.

---

## Identity and classification

| column | type | coverage | notes |
|---|---|---|---|
| `id` | INTEGER | 100% | primary key; `relationships_v2.to_series_id` points here |
| `title` | TEXT | 100% | primary display title |
| `native_title`, `romanized_title` | TEXT | partial | |
| `titles` | TEXT (JSON) | high | array of `{title, language, is_primary, traits, note}` — alt titles for search, not for similarity |
| `secondary_titles_*` | TEXT | sparse | 30+ per-language columns; ignore for modelling |
| `type` | TEXT | 100% | `manga` 363k, `novel` 61k, `manhwa` 59k, `other` 46k, `manhua` 25k, `oel` 2.5k |
| `status` | TEXT | 100% | `completed` 452k, `releasing` 71k, `unknown` 29k, `hiatus` 2.9k, `cancelled` 2.1k, `upcoming` 66 |
| `content_rating` | TEXT | 100% | `safe` 391k, `pornographic` 99k, `erotica` 56k, `suggestive` 12k |
| `year` | INTEGER | 99.5% | |
| `published_start_date`, `published_end_date` | TEXT | partial | plus `*_is_estimated` flags |

**`content_rating` is a required filter for any user-facing surface.** ~28% of
the catalog is `pornographic` or `erotica`. Decide the policy once, apply it at
candidate-generation time, and keep it out of the model.

`type` is a strong hard filter too — mixing `novel` into a "similar titles" rail
for a `manhwa` is usually wrong even when the tags match.

---

## Content signals

### `tags_v2` — the primary feature (97.1% active)

JSON array. Each element:

```json
{
  "id": 1872,
  "name": "Large Scale Battles",
  "level": 3,
  "weight": "incidental",
  "is_genre": false,
  "name_path": "Activities > Conflict > Large Scale Battles",
  "parent_id": 1902,
  "is_spoiler": false,
  "description": null,
  "is_explicit": true,
  "series_count": 43,
  "content_rating": "safe",
  "implied_by_tag_ids": []
}
```

Measured over a 20,000-title sample:

- **22.4 tags per title** on average (min 1, max 269)
- **~2,400 distinct tag names**
- `weight` distribution: `defining` 208k, `unweighted` 86k, `core` 64k,
  `recurrent` 51k, `incidental` 39k
- `level` distribution: 2 → 223k, 3 → 183k, 4 → 38k, 5 → 5k, 6 → 186
- `is_genre` is true for ~16% of entries

**Use the weights.** A term-frequency multiplier of roughly
`defining 3.0 / core 2.0 / recurrent 1.5 / incidental 1.0 / unweighted 1.0`
before TF-IDF measurably outperforms flat binary tags.

`series_count` is a built-in document frequency — a tag on 43 titles is far more
discriminative than `Romance` on 11k. TF-IDF already handles this, but it is
useful for hard filtering rare/garbage tags.

`is_spoiler` entries should be excluded from anything shown to a user, though
they are fine as model features.

`name_path` gives a taxonomy hierarchy. Rolling tags up to `level` 2 is a cheap
way to build a coarse genre-like vector; keeping `level` 3+ preserves the
specificity that makes recommendations feel deliberate.

### `genres` (91.5% active)

Flat JSON array of strings, 47 distinct values. Top: `Romance`, `Comedy`,
`Drama`, `Fantasy`, `Slice of Life`, `School Life`, `Action`, `Supernatural`,
`Shounen`, `Shoujo`, `Seinen`. Coarse but well-populated — good for
diversity constraints and hard filters, weak as a similarity signal on its own.

### `tags` (58.4% overall)

The same information as `tags_v2` with weights and hierarchy discarded, at much
lower coverage. **Prefer `tags_v2`.** Only fall back to `tags` for rows where
`tags_v2` is empty.

### `description` (62.5% active)

Free text, typically 500–1500 characters. Usable for a text-embedding model, but
note the coverage gap and that descriptions are marketing copy — they describe
premise, not taste. Combine with tags rather than replacing them.

### `authors` / `artists` (90.9% / high, active)

JSON arrays of names. A strong, under-used signal: "more by this author" is
often the single most clickable rail on a catalog product, and author identity
is a good similarity feature for a hybrid model.

### `publishers`

JSON array of `{name, note, type}` where `type` is `Original` / `English` /
`Other`. Licensing metadata, not a taste signal.

---

## Popularity and quality

| column | coverage (active) | notes |
|---|---|---|
| `popularity_global_current` | 99.3% | **rank**, 1 = most popular, range 1..300,818 |
| `popularity_type_current` | 99.3% | rank within `type` |
| `popularity_*_history_{1d,1w,1mo,3mo,6mo,1y}` | partial | past ranks — momentum/trending features live here |
| `rating` | 56.6% | 0–100 aggregate across sources |
| `popularity` | **0%** | dead column, ignore |

**These are ranks.** Convert before use:

```python
score = 1.0 / np.log1p(rank)          # smooth, bounded
score = 1.0 - rank / rank.max()       # linear
```

Trend features are the difference between `popularity_global_current` and a
history column — a title whose rank improved by 5,000 places in a month is
trending regardless of its absolute rank.

### Per-source ratings

Seven sources — `kitsu`, `anilist`, `shikimori`, `anime_planet`,
`manga_updates`, `my_anime_list`, `anime_news_network` — each with
`source_<name>_{id,cover,rating,rating_normalized,response,last_updated_at}`.

Use `*_rating_normalized` (integer, 0–100, comparable across sources). Ignore
`*_response` — those are raw cached API payloads, often kilobytes each, and they
are the main reason the database is 3.2 GB.

A count of non-null `source_*_id` values is itself a decent proxy for how
well-known a title is.

---

## `relationships_v2` — ground truth (100% populated, often `[]`)

JSON array. Each edge:

```json
{
  "id": "019e41ed-23fd-794f-8718-7059a532d4e3",
  "to_series_id": 1252,
  "relation_type": "sequel",
  "chronology": "unknown",
  "is_manual": true,
  "note": null,
  "published_start_date": null
}
```

~30% of active titles have at least one edge. Relation types, from a 60,000-row
active sample (~52k edges):

| type | count | strength |
|---|---|---|
| `parody` | 18,252 | **weak** — mostly doujinshi noise |
| `source` | 5,313 | strong |
| `alternative` | 4,396 | strong |
| `sequel` | 3,922 | strong |
| `side_story` | 2,969 | strong |
| `prequel` | 2,889 | strong |
| `main` | 2,461 | strong |
| `cameo` | 2,456 | **weak** |
| `parent` | 2,154 | strong |
| `spin_off` | 1,977 | strong |
| `contains` | 1,520 | strong |
| `other` | 1,327 | weak |
| `compilation` | 675 | moderate |
| `series` | 580 | strong |
| `adaptation` | 200 | strong |
| `remake`, `summary`, `crossover`, `character_focus` | ≤3 each | negligible |

`scripts/catalog.py` treats `parody`, `cameo`, and `other` as weak and excludes
them from ground truth by default (`--include-weak` overrides).

The denormalized `relationships_sequel`, `relationships_prequel`,
`relationships_spin_off`, `relationships_main_story`,
`relationships_alternative`, `relationships_side_story`,
`relationships_adaptation`, `relationships_other` columns hold plain id arrays
(e.g. `[1252]`) for a subset of the types. They are convenient but incomplete —
`relationships_v2` is authoritative. The bare `relationships` column is 0%
populated; ignore it.

Edges are **not reliably symmetric** in the source data. `scripts/catalog.py`
symmetrizes them when building ground truth, which is what you want for an
item-to-item task.

---

## Media and links (not modelling features)

`cover_raw_*` (url, size, width, height, format, blurhash, thumbhash) and
`cover_x{150,250,350}_x{1,2,3}` are display assets. `links_v2` is a JSON array
of external platform URLs. `anime`, `has_anime`, `anime_start`, `anime_end`
describe adaptation status — `has_anime` is a usable popularity proxy.

---

## Dead or unusable columns

| column | why |
|---|---|
| `genres_v2` | 0% populated |
| `popularity` | 0% populated |
| `relationships` | 0% populated (superseded by `relationships_v2`) |
| `source_*_response` | raw API payloads; huge, unstructured, already parsed into sibling columns |
| `secondary_titles_*` | 30+ sparse per-language columns |
| `cover_*` | display assets |

---

## Query template

Every query against this table should start from this shape:

```sql
SELECT id, title, type, year, status, content_rating,
       tags_v2, genres, authors, artists, description,
       rating, popularity_global_current, popularity_type_current,
       relationships_v2
FROM series
WHERE state = 'active'
```

Add `AND content_rating = 'safe'` for anything user-facing unless the product
has decided otherwise.

Cost note: the table has no indexes beyond the `id` rowid, and the JSON columns
are large. A full scan reads several GB. Build the Parquet cache once
(`scripts/catalog.py --build`) and work from that — it is ~40× smaller and loads
in seconds.
