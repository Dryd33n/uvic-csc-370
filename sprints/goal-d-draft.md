# Next-sprint goal D: MVDs and 4NF (draft)

Goal D adds two independent multivalued facts about a stock (tags and themes) and shows that adding one tag takes 3 rows before the 4NF decomposition and 1 row after.

| | |
| --- | --- |
| **Limitation** | The schema has no multivalued data, so we cannot yet show that we can apply a normal form beyond BCNF (Data Modelling, Level 3). |
| **Goal** | Add stock tags (`large-cap`, `dividend`, ...) and investment themes (`AI`, `services`, ...). They vary independently, so storing both in one table creates the MVD `ticker ↠ tag \| theme`. Decompose it into 4NF. |
| **Competency** | Data Modelling, Level 3: "Applies alternative normal forms when they better suit the application requirements." Also Level 2: "Eliminates data anomalies with effective normalisation." |
| **Objective measure** | Adding one tag to a stock with 3 themes inserts 3 rows before the decomposition and 1 row after. Joining the two new tables back gives exactly the original rows. |
| **Artifact** | `docs/4nf.md`, the new tables in the DDL, and `sql/4nf_demo.sql` |

## Why the single table is not in 4NF

`stock_tag_theme(ticker, tag, theme)` has key `(ticker, tag, theme)`. Tags and themes are independent, so every tag must be paired with every theme, which gives the MVD `ticker ↠ tag | theme`. `ticker` is not a superkey, so the table violates 4NF. It is still in BCNF, because it has no non-trivial FDs.

## Demo sketch

This was run on MySQL 8.0 in a throwaway database. It needs 8.0.31 or later for `EXCEPT`.

```sql
-- Before: one table
CREATE TABLE stock_tag_theme (
    ticker VARCHAR(10), tag VARCHAR(30), theme VARCHAR(30),
    PRIMARY KEY (ticker, tag, theme)
);
INSERT INTO stock_tag_theme VALUES
    ('AAPL', 'large-cap', 'AI'), ('AAPL', 'large-cap', 'consumer hardware'), ('AAPL', 'large-cap', 'services'),
    ('AAPL', 'dividend',  'AI'), ('AAPL', 'dividend',  'consumer hardware'), ('AAPL', 'dividend',  'services');

-- Add tag 'buyback': one row per theme
INSERT INTO stock_tag_theme
    SELECT DISTINCT ticker, 'buyback', theme FROM stock_tag_theme WHERE ticker = 'AAPL';
SELECT ROW_COUNT();  -- 3

-- After: 4NF decomposition
CREATE TABLE stock_tag   (ticker VARCHAR(10), tag   VARCHAR(30), PRIMARY KEY (ticker, tag));
CREATE TABLE stock_theme (ticker VARCHAR(10), theme VARCHAR(30), PRIMARY KEY (ticker, theme));
INSERT INTO stock_tag   SELECT DISTINCT ticker, tag   FROM stock_tag_theme WHERE tag <> 'buyback';
INSERT INTO stock_theme SELECT DISTINCT ticker, theme FROM stock_tag_theme;

INSERT INTO stock_tag VALUES ('AAPL', 'buyback');
SELECT ROW_COUNT();  -- 1

-- Lossless: the join gives back exactly the original 9 rows
SELECT COUNT(*) FROM stock_tag JOIN stock_theme USING (ticker);  -- 9
SELECT ticker, tag, theme FROM stock_tag JOIN stock_theme USING (ticker)
EXCEPT SELECT * FROM stock_tag_theme;                             -- 0 rows
```

## Depends on

- A primary key on `stock.ticker`, so `stock_tag` and `stock_theme` can reference it with foreign keys. The current `sql/ddl.sql` has no keys.
