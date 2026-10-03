# PaperTrade

PaperTrade is a paper-trading (simulated, fake-money) stock trading app, built as the semester project for CSC 370 (Database Systems) at UVic. The course grades the database design, so this repo is mostly SQL and design documents.

All data in this repo is fictional.

## Current state

The schema is an early draft: 4 tables in `sql/ddl.sql` (`user`, `stock`, `transaction`, `holds`) with no keys or constraints yet. Portfolios, limit orders, watchlists and the leaderboard are planned for later sprints.

## Run it

You need MySQL 8.0. The steps run `sql/ddl.sql`, `sql/seed.sql` and `sql/queries.sql` in that order.

> `sql/ddl.sql` starts with `DROP DATABASE IF EXISTS stock_trading;`. Don't run it against a server that holds a `stock_trading` database you want to keep.

### Option A: Docker (all platforms; use this on Windows)

Needs [Docker Desktop](https://www.docker.com/products/docker-desktop/) running. Open a terminal in the repo root and run these one at a time. They are the same on Windows (PowerShell or Command Prompt), macOS and Linux. On Windows, don't use Git Bash: it rewrites the `/sql` paths.

1. Start MySQL 8.0, then create the schema and load the sample data (`docker-compose.yml` runs `sql/ddl.sql` and then `sql/seed.sql`). This returns when the database is ready, after about 20-60 seconds; the first run also downloads the image.
   ```
   docker compose up -d --wait
   ```
2. Run the queries:
   ```
   docker compose exec db sh -c "mysql -uroot -prootpassword -t stock_trading < /sql/queries.sql"
   ```
3. Check the row counts:
   ```
   docker compose exec db mysql -uroot -prootpassword -t stock_trading -e "SELECT 'user' AS tbl, COUNT(*) AS n FROM user UNION ALL SELECT 'stock', COUNT(*) FROM stock UNION ALL SELECT 'transaction', COUNT(*) FROM transaction UNION ALL SELECT 'holds', COUNT(*) FROM holds"
   ```

Steps 2 and 3 print the warning `Using a password on the command line interface can be insecure`, which is expected. Step 3 should show `user` 9, `stock` 14, `transaction` 82, `holds` 22.

- **Step 1 fails** (for example `container papertrade-db exited`): an SQL file has an error. Run `docker compose logs db` to find it, fix the file, then reset as below.
- **After you edit `sql/ddl.sql` or `sql/seed.sql`:** the files only load when the database is first created. Run `docker compose down -v` to delete it, then step 1 again. Edits to `queries.sql` need no reset.
- **When you're done:** `docker compose down -v` deletes the container and its data.

### Option B: a local MySQL 8.0 server (macOS / Linux)

```bash
mysql -u root -p < sql/ddl.sql
mysql -u root -p < sql/seed.sql
mysql -u root -p < sql/queries.sql
```

To check, run the `SELECT` from step 5 in `mysql -u root -p stock_trading`. You should get the same counts.

## Files

| Path | What it is |
| --- | --- |
| `sql/ddl.sql` | Creates the `stock_trading` database and its tables |
| `sql/seed.sql` | Sample data: 9 users, 14 stocks (NASDAQ, NYSE, TSX), 82 trades, current holdings |
| `sql/queries.sql` | Demo queries (not written yet) |
| `docs/erd.md`, `docs/schema.svg` | ER diagram and its explanation |
| `docs/requirements.md` | Requirements (in progress) |
| `docs/normalization.md` | Functional dependencies and BCNF check (in progress) |
| `docker-compose.yml` | MySQL 8.0 with `ddl.sql` and `seed.sql` loaded (see Run it) |
| `sprints/` | Sprint reports and the next-sprint goal D draft |
| `.github/workflows/main.yml` | CI: runs the three SQL files on MySQL 8.0 on every push to `main` |

## AI use

TODO (team): which parts were written with AI help, which the team wrote, and how we checked the AI-written parts. Keep this consistent with `AI_USE.md`.
