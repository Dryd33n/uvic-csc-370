# Goal C: dependency preservation (draft)

Owner: C. First draft started by Shubin (B) so C has something to build on. The FD list and the BCNF vs 3NF example are done; the competency and a final decision are still open (see the end).

| | |
| --- | --- |
| **Limitation** | We picked BCNF without checking whether any FD got lost when we split tables. |
| **Goal** | For every FD, find the table that enforces it (or say it's lost). Find a case in our design where BCNF and 3NF give different answers and pick one with a reason. |
| **Competency** | _TODO (C): exact wording from Brightspace_ |
| **Objective measure** | A per-FD list with the enforcing table for each one, 0 FDs left unaccounted for, and the design choice justified from that list. |
| **Artifact** | `docs/dependency-preservation.md` (this file) |

## Quick recap

A decomposition preserves dependencies if every FD in F can be checked inside a single table, or follows from FDs that can. If an FD spans two tables, the only way to enforce it is a join or a trigger on every insert/update, which is exactly what normalization was supposed to save us from.

BCNF always gives a lossless decomposition (see goal B) but doesn't always preserve dependencies. 3NF can always do both, but may leave some redundancy.

## Per-FD list (planned 10-table schema)

These are the FDs from our requirements. Goal A will derive a proper minimal cover; if it comes out different, this list needs updating.

| # | FD | Enforced in | How |
| --- | --- | --- | --- |
| 1 | user_id → username, email | app_user | PRIMARY KEY (user_id) |
| 2 | username → user_id | app_user | UNIQUE (username) |
| 3 | email → user_id | app_user | UNIQUE (email) |
| 4 | exchange_code → exchange_name, country | exchange | PRIMARY KEY (exchange_code) |
| 5 | ticker → company_name, sector, exchange_code | stock | PRIMARY KEY (ticker) |
| 6 | portfolio_id → user_id, name, hidden | portfolio | PRIMARY KEY (portfolio_id) |
| 7 | order_id → portfolio_id, ticker, side, order_type, quantity, limit_price, status, placed_at | orders | PRIMARY KEY (order_id) |
| 8 | trade_id → order_id, fill_qty, fill_price, filled_at | trade | PRIMARY KEY (trade_id) |
| 9 | watchlist_id → user_id, name | watchlist | PRIMARY KEY (watchlist_id) |
| 10 | watchlist_id, ticker → added_at | watchlist_item | PRIMARY KEY (watchlist_id, ticker) |
| 11 | ticker, quoted_at → price | price_quote | PRIMARY KEY (ticker, quoted_at) |
| 12 | portfolio_id, snapshot_date → cash, holdings_value | portfolio_snapshot | PRIMARY KEY (portfolio_id, snapshot_date) |

Every FD's attributes sit inside one table, so all 12 are preserved, and each one is enforced by a key, not a trigger.

There are also FDs that cross tables, like trade_id → portfolio_id. Those don't need their own table, because they follow from FDs we already keep: trade_id → order_id (8) and order_id → portfolio_id (7), so by transitivity trade_id → portfolio_id. That's the "or follows from" part of the definition. Same thing for trade_id → ticker and ticker → exchange_name.

## Where BCNF and 3NF differ

Our current requirements don't hit this, but there's a rule we talked about adding that does: **a stock can only be on one of a user's watchlists** (so you can't have AAPL on both "tech" and "dividends").

Take R(user_id, ticker, watchlist_id) with:

- watchlist_id → user_id (a watchlist belongs to one user)
- user_id, ticker → watchlist_id (the new rule)

Candidate keys: {user_id, ticker} and {watchlist_id, ticker}.

- **3NF?** Yes. watchlist_id → user_id has a determinant that isn't a superkey, but user_id is part of a candidate key (prime), so 3NF allows it.
- **BCNF?** No, for the same FD: watchlist_id isn't a superkey.

The BCNF decomposition on watchlist_id → user_id gives watchlist(watchlist_id, user_id) and watchlist_item(watchlist_id, ticker), which is basically what we already have. It's lossless (goal B), but **FD user_id, ticker → watchlist_id is lost**: no table has user_id and ticker together, so no key can enforce it.

Tested on MySQL 8 in a throwaway database:

```sql
-- BCNF: the split we use
CREATE TABLE watchlist      (watchlist_id INT PRIMARY KEY, user_id INT NOT NULL);
CREATE TABLE watchlist_item (watchlist_id INT, ticker VARCHAR(10), PRIMARY KEY (watchlist_id, ticker));
INSERT INTO watchlist VALUES (1, 1), (2, 1);
INSERT INTO watchlist_item VALUES (1, 'AAPL');
INSERT INTO watchlist_item VALUES (2, 'AAPL');   -- breaks the rule, but it's accepted

SELECT w.user_id, i.ticker, COUNT(*) AS lists
FROM watchlist w JOIN watchlist_item i USING (watchlist_id)
GROUP BY w.user_id, i.ticker;                    -- user 1, AAPL, 2 lists

-- 3NF: one table, both keys enforced
CREATE TABLE watchlist_entry (
    user_id INT, ticker VARCHAR(10), watchlist_id INT,
    PRIMARY KEY (user_id, ticker),
    UNIQUE (watchlist_id, ticker)
);
INSERT INTO watchlist_entry VALUES (1, 'AAPL', 1);
INSERT INTO watchlist_entry VALUES (1, 'AAPL', 2);  -- ERROR 1062: Duplicate entry '1-AAPL'
```

The catch with the 3NF table is the other direction: watchlist_id → user_id isn't a key there, so user_id repeats for every stock on a list, and nothing stops `(2, 'MSFT', 1)`, which says watchlist 1 suddenly belongs to user 2. So either way one FD needs a trigger:

| Option | Rule it can't enforce with a key | Redundancy |
| --- | --- | --- |
| BCNF (current) | user_id, ticker → watchlist_id | none |
| 3NF (one table) | watchlist_id → user_id | user_id repeated per stock |

## Still to do (C)

- Copy the competency wording from Brightspace.
- Decide: keep BCNF and add a trigger for the one-list rule, or go 3NF. My vote is BCNF + trigger, since the rule only matters on insert into watchlist_item and the 3NF version can corrupt ownership, which is worse. But it's your call.
- Ask the team whether we actually want the one-list rule. If not, the example still shows the difference, it just doesn't change the schema.
- Re-check the per-FD list once goal A's minimal cover is done and the 10 tables are in the DDL.
