# Seed Data Generator

`generate_seed.py` writes `sql/seed.sql` with sample data for the schema in `sql/ddl.sql`. It needs Python 3.9+ and no packages (the optional `--tui` needs Textual, see below).

## Interactive mode (`--tui`)

```
py -m pip install -r tools/requirements.txt   # once: installs Textual
py tools/generate_seed.py --tui
```

## Usage

Run from the repo root (`py` on Windows, `python3` on macOS/Linux):

```
py tools/generate_seed.py                                  # write sql/seed.sql with the defaults
py tools/generate_seed.py --users 50 --days 120 --seed 7   # a larger data set
py tools/generate_seed.py -o -                             # print to stdout instead
```

The same options always produce the same file, so commit `sql/seed.sql` after regenerating. The command that made the current file is in its first lines.

After regenerating, reload the database: `docker compose down -v`, then `docker compose up -d --wait`.



Opens a terminal editor with the options on the left and a live preview on the right, updated as you type:

- **Cards:** total rows, file size, buys / sells and median final cash.
- **Overview tab:** rows per table with details (date range, NULL target prices, order statuses), plus charts of trades per day, final cash per user and average closing price.
- **SQL preview tab:** pick a table to see its generated `INSERT`s, syntax-highlighted.
- **Equivalent command:** the CLI command that writes the same file, ready to copy.

Invalid options are flagged in red and block writing. **Ctrl+S** writes the file, **Ctrl+R** resets to the starting options, **Ctrl+Q** quits. Options given on the command line, e.g. `--tui --users 40`, become the starting values.

## Options

| Option | Default | Meaning |
|--------|---------|---------|
| `--tui` | off | Open the interactive editor |
| `-o`, `--output` | `sql/seed.sql` | Output file, or `-` for stdout |
| `--seed` | `370` | Random seed |
| `--users` | `12` | Number of users |
| `--days` | `60` | Trading days (weekdays) of price history |
| `--end-date` | `2026-09-30` | Last price and trade date; can't be in the future |
| `--trades` | `8` | Average trades per portfolio |
| `--max-portfolios` | `3` | Max portfolios per user |
| `--max-watch` | `5` | Max watchlist entries per user |
| `--max-orders` | `2` | Max pending or cancelled limit orders per portfolio |
| `--executed` | `3` | Limit orders executed when the seed loads |

## What it generates

- **Exchanges and stocks:** NASDAQ, NYSE and TSX, and 14 fixed stocks.
- **Price history:** one row per stock per trading day, from a random walk.
- **Users and portfolios:** each user starts with the $100,000 default cash and has 1 to `--max-portfolios` portfolios.
- **Trades:** in time order, at a price within that day's low–high range. TSX stocks are watch-only, since cash is in one currency.
- **Watchlist entries:** some have a target price, others are `NULL`.
- **Limit orders:** pending and cancelled orders are inserted directly. The `--executed` orders are inserted as pending, then updated to `executed` at the end, so the database trigger creates their trades.

## Why the data always loads

The schema's triggers reject a buy that costs more than the user's cash, a sell of more shares than the portfolio holds, and dates in the future. The generator tracks each user's cash and each portfolio's holdings as it creates trades, so it never writes a row the triggers would reject. `user.cash_balance` is not set directly: the triggers update it as each trade loads.
