# PaperTrade

PaperTrade is a paper-trading (simulated, fake-money) stock trading app, built as the semester project for CSC 370 (Database Systems) at UVic. The course grades the database design, so this repo is mostly SQL and design documents.

All data in this repo is fictional.

## Current state

The schema has 4 tables in `sql/ddl.sql` (`user`, `stock`, `transaction`, `holds`) with primary keys, foreign keys, `NOT NULL`, a `UNIQUE` email and `CHECK` constraints on quantities and prices. `sql/constraint_tests.sql` shows each of these rejecting invalid data. Portfolios, limit orders, watchlists and the leaderboard are planned for later sprints.

## Run it

You need MySQL 8.0. The steps run `sql/ddl.sql`, `sql/seed.sql` and `sql/queries.sql` in that order.

> `sql/ddl.sql` starts with `DROP DATABASE IF EXISTS stock_trading;`. Don't run it against a server that holds a `stock_trading` database you want to keep.

### Option A: Docker (all platforms; use this on Windows)

Needs [Docker Desktop](https://www.docker.com/products/docker-desktop/) running. Open a terminal in the repo root and run these one at a time. They are the same on Windows (PowerShell or Command Prompt), macOS and Linux. On Windows, don't use Git Bash: it rewrites the `/sql` paths.

1. Start MySQL 8.0, then create the schema and load the sample data (`docker-compose.yml` runs `sql/ddl.sql` and then `sql/seed.sql`). This returns when the database is ready, after about 20-60 seconds; the first run also downloads the image.
   ```
   docker compose up -d --wait
   ```
2. Run the goal D queries. Each one in `sql/queries.sql` is written in relational algebra first (in the comment above it) and shows the result it should return. Expect three tables for Alice: her 4 positions valued at the closing price, the gain or loss on each, and her 14 trades.
   ```
   docker compose exec db sh -c "mysql -uroot -prootpassword -t stock_trading < /sql/queries.sql"
   ```
3. Check the row counts:
   ```
   docker compose exec db mysql -uroot -prootpassword -t stock_trading -e "SELECT 'user' AS tbl, COUNT(*) AS n FROM user UNION ALL SELECT 'stock', COUNT(*) FROM stock UNION ALL SELECT 'transaction', COUNT(*) FROM transaction UNION ALL SELECT 'holds', COUNT(*) FROM holds"
   ```

4. Run the constraint tests. Each of the 21 statements in `sql/constraint_tests.sql` breaks one constraint, and the test passes only if MySQL rejects it with the expected error code. Expect `22 | 22` passed (the extra check confirms the server runs in strict mode), and the counts printed at the end should still be 9 / 14 / 82 / 22. The file rolls back at the end, so it never changes the data. If any test fails, it ends with `ERROR 1644 ... Constraint tests failed`.
   ```
   docker compose exec db sh -c "mysql -uroot -prootpassword -t stock_trading < /sql/constraint_tests.sql"
   ```

Steps 2-4 print the warning `Using a password on the command line interface can be insecure`, which is expected. Step 3 should show `user` 9, `stock` 14, `transaction` 82, `holds` 22.

- **Step 1 fails** (for example `container papertrade-db exited`): an SQL file has an error. Run `docker compose logs db` to find it, fix the file, then reset as below.
- **After you edit `sql/ddl.sql` or `sql/seed.sql`:** the files only load when the database is first created. Run `docker compose down -v` to delete it, then step 1 again. Edits to `queries.sql` or `constraint_tests.sql` need no reset.
- **When you're done:** `docker compose down -v` deletes the container and its data.

### Option B: a local MySQL 8.0 server (macOS / Linux)

```bash
mysql -u root -p < sql/ddl.sql
mysql -u root -p < sql/seed.sql
mysql -u root -p < sql/queries.sql
mysql -u root -p -t stock_trading < sql/constraint_tests.sql
```

To check, run the `SELECT` from step 3 in `mysql -u root -p stock_trading`. You should get the same counts.

## Files

| Path | What it is |
| --- | --- |
| `sql/ddl.sql` | Creates the `stock_trading` database and its tables |
| `sql/seed.sql` | Sample data: 9 users, 14 stocks (NASDAQ, NYSE, TSX), 82 trades, current holdings |
| `sql/queries.sql` | Goal D: portfolio value, gain/loss per position and trade history, each written in relational algebra and then SQL, with the expected results |
| `sql/constraint_tests.sql` | 21 statements that each break one constraint and must be rejected with the expected error code, plus a strict-mode check; run by CI |
| `docs/Candidate Keys/` | Goal A: functional dependencies, closures, superkeys and candidate keys, checked against `ddl.sql` (`.tex` and `.pdf`) |
| `docs/Minimal Basis and FD Projection/` | Goal B: minimal basis, FD projection onto each table, dependency preservation |
| `docs/Lossless Join Proof/` | Goal B: decomposition of the universal relation and the chase test |
| `docs/Relational Algebra Constraints/` | Goal C: key, foreign key and domain constraints in relational algebra |
| `docs/schema.svg` | ER diagram |
| `docker-compose.yml` | MySQL 8.0 with `ddl.sql` and `seed.sql` loaded (see Run it) |
| `sprints/` | Sprint reports |
| `.github/workflows/main.yml` | CI: on every push to `main`, loads `ddl.sql` and `seed.sql` on MySQL 8.0, runs `constraint_tests.sql`, and runs `queries.sql` if it exists |

## AI use

See `AI_USE.md`.
