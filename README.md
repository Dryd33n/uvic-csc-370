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

1. Start an empty MySQL 8.0 server:
   ```
   docker run -d --name papertrade-db -e MYSQL_ROOT_PASSWORD=rootpassword mysql:8.0
   ```
2. Copy the `sql` folder into it:
   ```
   docker cp sql/. papertrade-db:/sql
   ```
3. Wait until the server is ready. This returns after about 10-60 seconds; the first start takes longest.
   ```
   docker exec papertrade-db sh -c "until mysqladmin ping -h127.0.0.1 --silent; do sleep 2; done"
   ```
4. Create the schema, load the sample data, and run the queries:
   ```
   docker exec papertrade-db sh -c "mysql -uroot -prootpassword < /sql/ddl.sql"
   docker exec papertrade-db sh -c "mysql -uroot -prootpassword < /sql/seed.sql"
   docker exec papertrade-db sh -c "mysql -uroot -prootpassword < /sql/queries.sql"
   ```
5. Check the row counts:
   ```
   docker exec papertrade-db mysql -uroot -prootpassword -t stock_trading -e "SELECT 'user' AS tbl, COUNT(*) AS n FROM user UNION ALL SELECT 'stock', COUNT(*) FROM stock UNION ALL SELECT 'transaction', COUNT(*) FROM transaction UNION ALL SELECT 'holds', COUNT(*) FROM holds"
   ```

Steps 4 and 5 print only the warning `Using a password on the command line interface can be insecure`, which is expected. Step 5 should show `user` 9, `stock` 14, `transaction` 82, `holds` 22.

After you edit a file in `sql/`, repeat step 2, then steps 4 and 5. To delete the database when you're done, run `docker rm -f papertrade-db`.

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
| `sprints/` | Sprint reports |
| `.github/workflows/main.yml` | CI: runs the three SQL files on MySQL 8.0 on every push to `main` |

## AI use

TODO (team): which parts were written with AI help, which the team wrote, and how we checked the AI-written parts. Keep this consistent with `AI_USE.md`.
