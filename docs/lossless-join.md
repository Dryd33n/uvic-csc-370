# Goal B: lossless join (draft)

Owner: Shubin (B)

Right now we split tables apart because it "looks right" for BCNF, but we never actually proved that joining them back gives the original data. This goal runs the chase test on the three decompositions in our planned schema and backs each one up with a SQL join-back check (`sql/lossless_check.sql`).

|                       |                                                                                                                                                                                                                                                                           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Limitation**        | Our decompositions are not proven lossless. We just assumed it.                                                                                                                                                                                                           |
| **Goal**              | Chase test on stock/exchange, orders/trade and watchlist/watchlist_item.                                                                                                                                                                                                  |
| **Competency**        | Data Modelling, Level 2: "Eliminates data anomalies with effective normalisation." A decomposition that isn't lossless creates spurious tuples, which is its own kind of anomaly, so proving lossless join is part of normalising properly and not just splitting tables. |
| **Objective measure** | Each final tableau has a row of all distinguished variables (all `a`s). The SQL join-back returns exactly the original rows: same count, 0 missing, 0 extra.                                                                                                              |
| **Artifact**          | `docs/lossless-join.md` (this file) and `sql/lossless_check.sql`                                                                                                                                                                                                          |

## How the chase works (quick recap from lecture)

For a decomposition of R into R1, ..., Rk:

1. Make a tableau with one row per Ri and one column per attribute of R.
2. In row i, put the distinguished symbol `a` in every column that is in Ri, and a unique `b` (subscripted by row and column) everywhere else.
3. Repeatedly apply the FDs: if two rows agree on the left side of an FD, make them agree on the right side. If one of the two symbols is an `a`, both become the `a`. Otherwise pick one of the `b`s.
4. If some row ends up all `a`s, the decomposition is lossless. If nothing else can change and no row is all `a`s, it's lossy.

For binary splits there's also the shortcut: R1 ∩ R2 → R1 or R1 ∩ R2 → R2. I used it to double check each answer below, but the chase is the actual evidence for this goal.

## 1. stock / exchange

R(ticker, company_name, exchange_code, exchange_name, country)

FDs:

- ticker → company_name, exchange_code
- exchange_code → exchange_name, country

Decomposition:

- stock(ticker, company_name, exchange_code)
- exchange(exchange_code, exchange_name, country)

Starting tableau:

|          | ticker | company_name | exchange_code | exchange_name | country |
| -------- | ------ | ------------ | ------------- | ------------- | ------- |
| stock    | a1     | a2           | a3            | b14           | b15     |
| exchange | b21    | b22          | a3            | a4            | a5      |

Both rows have `a3` in exchange_code, so apply exchange_code → exchange_name, country. Row "stock" gets `b14 → a4` and `b15 → a5`:

|          | ticker | company_name | exchange_code | exchange_name | country |
| -------- | ------ | ------------ | ------------- | ------------- | ------- |
| stock    | a1     | a2           | a3            | **a4**        | **a5**  |
| exchange | b21    | b22          | a3            | a4            | a5      |

Row "stock" is all `a`s → **lossless**. (Shortcut: stock ∩ exchange = {exchange_code}, which is the key of exchange. ✔)

## 2. orders / trade

This is the one that matters most since an order can be filled in several pieces (partial fills), so one order has many trades.

R(trade_id, order_id, portfolio_id, ticker, side, limit_price, fill_qty, fill_price)

8 columns made the table too wide, so I'm using letters:
T = trade_id, O = order_id, P = portfolio_id, K = ticker, S = side, L = limit_price, Q = fill_qty, F = fill_price

FDs:

- T → O, Q, F
- O → P, K, S, L

Decomposition:

- orders(O, P, K, S, L)
- trade(T, O, Q, F)

Starting tableau:

|        | T   | O   | P   | K   | S   | L   | Q   | F   |
| ------ | --- | --- | --- | --- | --- | --- | --- | --- |
| orders | b11 | a2  | a3  | a4  | a5  | a6  | b17 | b18 |
| trade  | a1  | a2  | b23 | b24 | b25 | b26 | a7  | a8  |

The rows agree on O (`a2`), so apply O → P, K, S, L. Row "trade" gets `a3, a4, a5, a6`:

|        | T   | O   | P      | K      | S      | L      | Q   | F   |
| ------ | --- | --- | ------ | ------ | ------ | ------ | --- | --- |
| orders | b11 | a2  | a3     | a4     | a5     | a6     | b17 | b18 |
| trade  | a1  | a2  | **a3** | **a4** | **a5** | **a6** | a7  | a8  |

Row "trade" is all `a`s → **lossless**. (Shortcut: orders ∩ trade = {order_id} → orders. ✔)

One thing I noticed while doing the SQL part: an order that hasn't filled yet (an open limit order) has no trades, so it doesn't show up in `orders ⋈ trade`. That isn't the decomposition losing data though. The original R is one row per trade, so it couldn't store an unfilled order in the first place (without nulls for T, Q, F). That's actually one more reason for splitting them. The SQL file shows this at the end of section 2.

## 3. watchlist / watchlist_item

R(watchlist_id, user_id, name, ticker, added_at)

FDs:

- watchlist_id → user_id, name
- watchlist_id, ticker → added_at

Decomposition:

- watchlist(watchlist_id, user_id, name)
- watchlist_item(watchlist_id, ticker, added_at)

Starting tableau:

|                | watchlist_id | user_id | name | ticker | added_at |
| -------------- | ------------ | ------- | ---- | ------ | -------- |
| watchlist      | a1           | a2      | a3   | b14    | b15      |
| watchlist_item | a1           | b22     | b23  | a4     | a5       |

Both rows have `a1` for watchlist_id, so apply watchlist_id → user_id, name. Row "watchlist_item" gets `a2, a3`:

|                | watchlist_id | user_id | name   | ticker | added_at |
| -------------- | ------------ | ------- | ------ | ------ | -------- |
| watchlist      | a1           | a2      | a3     | b14    | b15      |
| watchlist_item | a1           | **a2**  | **a3** | a4     | a5       |

Row "watchlist_item" is all `a`s → **lossless**. The second FD never got used, which makes sense because only one row has `a` for ticker.

## Sanity check: a decomposition that should fail

To make sure I wasn't just getting "lossless" every time, I tried a bad split of the same order/trade relation, joining on ticker instead of order_id:

- r1(T, K, Q, F)
- r2(O, P, K, S, L)

|     | T   | O   | P   | K   | S   | L   | Q   | F   |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r1  | a1  | b12 | b13 | a4  | b15 | b16 | a7  | a8  |
| r2  | b21 | a2  | a3  | a4  | a5  | a6  | b27 | b28 |

The only column the rows share is K, and K isn't the left side of any FD. T → ... and O → ... can't fire because only one row has an `a` in T and only one row has an `a` in O. So nothing changes, no row is all `a`s → **lossy**. In SQL this shows up as spurious rows: two AAPL trades from different orders join with each other's order (section 4 of the SQL file).

## Summary

| Decomposition                   | Common attribute(s) | FD used in the chase                               | Result   |
| ------------------------------- | ------------------- | -------------------------------------------------- | -------- |
| stock / exchange                | exchange_code       | exchange_code → exchange_name, country             | lossless |
| orders / trade                  | order_id            | order_id → portfolio_id, ticker, side, limit_price | lossless |
| watchlist / watchlist_item      | watchlist_id        | watchlist_id → user_id, name                       | lossless |
| r1 / r2 (bad split, on purpose) | ticker              | none                                               | lossy    |

## SQL join-back check

`sql/lossless_check.sql` builds each original relation R with sample rows, projects it into the decomposed tables, joins them back and compares with R using `EXCEPT` in both directions. It runs in its own database (`lossless_check`) so it doesn't touch `stock_trading`. It needs MySQL 8.0.31+ for `EXCEPT`.

```
mysql -u root -p -t < sql/lossless_check.sql
```

With Docker (see the README) it's:

```
docker compose exec db sh -c "mysql -uroot -prootpassword -t < /sql/lossless_check.sql"
```

What I got (5 sample rows each):

| decomposition              | original_rows | joined_rows | missing | extra | result |
| -------------------------- | ------------- | ----------- | ------- | ----- | ------ |
| stock / exchange           | 5             | 5           | 0       | 0     | PASS   |
| orders / trade             | 5             | 5           | 0       | 0     | PASS   |
| watchlist / watchlist_item | 5             | 5           | 0       | 0     | PASS   |
| bad split on ticker        | 5             | 8           | 0       | 3     | FAIL   |

The 3 extra rows in the bad split are all AAPL: trades 1 and 2 (order 101) get paired with order 102 and trade 3 (order 102) gets paired with order 101. That matches the chase saying it's lossy. The script drops the `lossless_check` database at the end.

## Limitations / what's left

- The SQL check only shows the join is lossless for _this_ sample data. It can't prove it for every instance. The chase is the actual proof, the SQL is just evidence that matches it.
- The tables here are from our planned schema, not the current `sql/ddl.sql` (which only has 4 tables and no exchange, orders, trade or watchlist yet). When those tables go into the DDL next sprint, the column names here need to match.
- The FDs come from our requirements. If goal A (formal FD analysis) finds a different minimal cover, I'll redo the chase with those FDs.
- The competency wording is the same Level 2 quote we used for goal D. Still need to double check on Brightspace whether there's a more specific module-level one for lossless decomposition.
