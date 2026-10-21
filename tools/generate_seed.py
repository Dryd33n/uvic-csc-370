"""Generate sql/seed.sql for the stock_trading schema in sql/ddl.sql.

The output is deterministic for a given --seed, so CI and every teammate load
the same data. Trades are simulated in time order against each user's cash and
each portfolio's holdings, so every row passes the triggers in ddl.sql
(C.7.7 cash, C.7.8 holdings, C.5.7 / C.7.10 no future dates).

Usage:
    py tools/generate_seed.py                      # writes sql/seed.sql
    py tools/generate_seed.py --users 50 --days 120 --seed 7
    py tools/generate_seed.py -o -                 # print to stdout
"""

import argparse
import random
import sys
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from decimal import ROUND_HALF_UP, Decimal
from itertools import product
from pathlib import Path

CENT = Decimal("0.01")
STARTING_CASH = Decimal("100000.00")  # matches the DEFAULT on user.cash_balance (C.1.6)
REPO_ROOT = Path(__file__).resolve().parent.parent

EXCHANGES = [
    ("NASDAQ", "Nasdaq Stock Market", "United States", "USD"),
    ("NYSE", "New York Stock Exchange", "United States", "USD"),
    ("TSX", "Toronto Stock Exchange", "Canada", "CAD"),
]

# (ticker, company, sector, exchange, starting price)
STOCKS = [
    ("AAPL", "Apple Inc.", "Technology", "NASDAQ", 217.85),
    ("MSFT", "Microsoft Corporation", "Technology", "NASDAQ", 483.39),
    ("NVDA", "NVIDIA Corporation", "Semiconductors", "NASDAQ", 178.69),
    ("AMZN", "Amazon.com, Inc.", "Consumer Discretionary", "NASDAQ", 193.27),
    ("GOOGL", "Alphabet Inc. Class A", "Communication Services", "NASDAQ", 176.16),
    ("COST", "Costco Wholesale Corporation", "Consumer Staples", "NASDAQ", 928.28),
    ("JPM", "JPMorgan Chase & Co.", "Financials", "NYSE", 268.04),
    ("KO", "The Coca-Cola Company", "Consumer Staples", "NYSE", 66.05),
    ("XOM", "Exxon Mobil Corporation", "Energy", "NYSE", 118.59),
    ("JNJ", "Johnson & Johnson", "Health Care", "NYSE", 162.19),
    ("DIS", "The Walt Disney Company", "Communication Services", "NYSE", 89.57),
    ("CAT", "Caterpillar Inc.", "Industrials", "NYSE", 386.83),
    ("CNR", "Canadian National Railway Company", "Industrials", "TSX", 154.13),
    ("ATD", "Alimentation Couche-Tard Inc.", "Consumer Staples", "TSX", 74.32),
]

# Cash is held in one currency, so CAD-listed stocks are watch-only
TRADEABLE_EXCHANGES = {"NASDAQ", "NYSE"}

FIRST_NAMES = [
    "Alice", "Ben", "Chika", "Diego", "Emma", "Farhan", "Grace", "Hiroshi", "Isla",
    "Jonas", "Keira", "Liam", "Maya", "Noah", "Olivia", "Priya", "Quinn", "Rafael",
    "Sofia", "Theo", "Uma", "Victor", "Wren", "Ximena", "Yusuf", "Zoe",
]
LAST_NAMES = [
    "Martin", "Carter", "Okafor", "Ramirez", "Tremblay", "Siddiqui", "Liu", "Tanaka",
    "MacDonald", "Becker", "Nguyen", "O'Brien", "Kowalski", "Haddad", "Singh",
    "Rossi", "Andersen", "Moreau", "Kim", "Fernandes",
]
PORTFOLIO_NAMES = ["TFSA", "RRSP", "Margin", "Day Trading", "Long Term", "Dividend"]


@dataclass
class Bar:
    """One stock_price_history row."""
    open: Decimal
    close: Decimal
    high: Decimal
    low: Decimal
    volume: int


@dataclass
class Portfolio:
    portfolio_id: int
    user_id: int
    name: str
    created_at: datetime
    holdings: dict = field(default_factory=dict)  # ticker -> shares held


def money(x) -> Decimal:
    """Round like MySQL's ROUND(x, 2) on DECIMAL (half away from zero)."""
    return Decimal(str(x)).quantize(CENT, rounding=ROUND_HALF_UP)


def sql_value(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, (int, Decimal)):
        return str(v)
    if isinstance(v, datetime):
        return f"'{v:%Y-%m-%d %H:%M:%S}'"
    if isinstance(v, date):
        return f"'{v:%Y-%m-%d}'"
    return "'" + str(v).replace("\\", "\\\\").replace("'", "''") + "'"


def insert(table: str, columns: list, rows: list, chunk: int = 500) -> str:
    """Multi-row INSERTs, split into chunks to keep statements a sane size."""
    if not rows:
        return f"-- (no {table} rows)\n"
    cols = ", ".join(f"`{c}`" for c in columns)
    out = []
    for i in range(0, len(rows), chunk):
        values = ",\n".join("    (" + ", ".join(sql_value(v) for v in r) + ")" for r in rows[i:i + chunk])
        out.append(f"INSERT INTO `{table}` ({cols}) VALUES\n{values};\n")
    return "\n".join(out)


def section(title: str) -> str:
    bar = "-- " + "-" * 53
    return f"\n{bar}\n-- {title}\n{bar}\n"


def trading_days(end: date, count: int) -> list:
    days, d = [], end
    while len(days) < count:
        if d.weekday() < 5:
            days.append(d)
        d -= timedelta(days=1)
    return days[::-1]


def random_time_on(rng: random.Random, d: date) -> datetime:
    """A time during market hours, 09:30-16:00."""
    seconds = rng.randint(0, 6 * 3600 + 30 * 60)
    return datetime.combine(d, time(9, 30)) + timedelta(seconds=seconds)


def price_history(rng: random.Random, start: float, days: list) -> dict:
    """Random walk of daily bars that satisfy C.5.3-C.5.6."""
    bars, prev_close = {}, start
    for d in days:
        open_ = max(prev_close * (1 + rng.gauss(0, 0.005)), 1.0)
        close = max(open_ * (1 + rng.gauss(0, 0.015)), 1.0)
        o, c = money(open_), money(close)
        high = max(money(max(open_, close) * (1 + abs(rng.gauss(0, 0.006)))), o, c)
        low = min(money(min(open_, close) * (1 - abs(rng.gauss(0, 0.006)))), o, c)
        bars[d] = Bar(o, c, high, max(low, CENT), rng.randint(2_000_000, 60_000_000))
        prev_close = close
    return bars


@dataclass
class Seed:
    """Everything build() generates; render() turns it into SQL."""
    days: list
    history: dict           # ticker -> {date: Bar}
    users: list             # (user_id, name, email)
    portfolios: list        # Portfolio
    transactions: list      # (transaction_id, portfolio_id, ticker, type, quantity, price, executed_at)
    watchlist: list         # (user_id, ticker, target_price, added_at)
    orders: list            # (order_id, portfolio_id, ticker, type, target_price, quantity, status, created_at)
    to_execute: list        # order_ids set to 'executed' at the end of the load
    cash: dict              # user_id -> cash_balance once the load finishes


def build(args) -> Seed:
    rng = random.Random(args.seed)
    days = trading_days(args.end_date, args.days)
    first_day, last_day = days[0], days[-1]

    # stock_price_history
    history = {t: price_history(rng, p, days) for t, _, _, _, p in STOCKS}
    tradeable = [t for t, _, _, ex, _ in STOCKS if ex in TRADEABLE_EXCHANGES]

    # user
    names = rng.sample(list(product(FIRST_NAMES, LAST_NAMES)), args.users)
    users, cash = [], {}
    for uid, (first, last) in enumerate(names, start=1):
        handle = f"{first}.{last}".lower().replace("'", "")
        users.append((uid, f"{first} {last}", f"{handle}{uid}@example.com"))
        cash[uid] = STARTING_CASH

    # portfolio: opened before the first trading day so every trade comes after it
    portfolios = []
    for uid, *_ in users:
        for name in rng.sample(PORTFOLIO_NAMES, rng.randint(1, args.max_portfolios)):
            opened = random_time_on(rng, first_day - timedelta(days=rng.randint(1, 30)))
            portfolios.append(Portfolio(len(portfolios) + 1, uid, name, opened))

    # transaction: random trade times, replayed in order against cash and holdings
    events = sorted(
        (random_time_on(rng, rng.choice(days)), p.portfolio_id)
        for p in portfolios
        for _ in range(rng.randint(0, 2 * args.trades))
    )
    by_id = {p.portfolio_id: p for p in portfolios}
    transactions = []
    for executed_at, pid in events:
        p = by_id[pid]
        held = [t for t, q in p.holdings.items() if q > 0]

        if held and rng.random() < 0.4:
            ticker = rng.choice(held)
            day_bar = history[ticker][executed_at.date()]
            price = money(rng.uniform(float(day_bar.low), float(day_bar.high)))
            qty = rng.randint(1, p.holdings[ticker])
            kind = "sell"
        else:
            ticker = rng.choice(tradeable)
            day_bar = history[ticker][executed_at.date()]
            price = money(rng.uniform(float(day_bar.low), float(day_bar.high)))
            budget = cash[p.user_id] * Decimal(str(rng.uniform(0.02, 0.15)))
            qty = int(budget / price)
            kind = "buy"
            if qty < 1:
                continue

        cost = money(qty * price)
        if kind == "buy":
            assert cost <= cash[p.user_id]  # C.7.7
            cash[p.user_id] -= cost
            p.holdings[ticker] = p.holdings.get(ticker, 0) + qty
        else:
            assert qty <= p.holdings[ticker]  # C.7.8
            cash[p.user_id] += cost
            p.holdings[ticker] -= qty
        transactions.append((len(transactions) + 1, pid, ticker, kind, qty, price, executed_at))

    # watchlist
    watchlist = []
    for uid, *_ in users:
        for ticker in sorted(rng.sample([s[0] for s in STOCKS], rng.randint(0, args.max_watch))):
            close = history[ticker][last_day].close
            target = None if rng.random() < 0.3 else money(float(close) * rng.uniform(0.85, 1.15))
            watchlist.append((uid, ticker, target, random_time_on(rng, rng.choice(days))))

    # limit_order: pending and cancelled orders are inserted as-is
    recent = days[-min(10, len(days)):]
    orders = []

    def add_order(p, ticker, kind, target, qty, status):
        created = random_time_on(rng, rng.choice(recent))
        orders.append((len(orders) + 1, p.portfolio_id, ticker, kind, target, qty, status, created))

    for p in portfolios:
        for _ in range(rng.randint(0, args.max_orders)):
            held = [t for t, q in p.holdings.items() if q > 0]
            status = "cancelled" if rng.random() < 0.25 else "pending"
            if held and rng.random() < 0.4:
                ticker = rng.choice(held)
                close = float(history[ticker][last_day].close)
                add_order(p, ticker, "sell", money(close * rng.uniform(1.02, 1.10)),
                          rng.randint(1, p.holdings[ticker]), status)
            else:
                ticker = rng.choice(tradeable)
                close = float(history[ticker][last_day].close)
                add_order(p, ticker, "buy", money(close * rng.uniform(0.90, 0.98)),
                          rng.randint(1, 20), status)

    # limit_order executed at load time: inserted pending, then UPDATEd so the
    # trigger creates the transaction (C.8.7) and re-checks cash/holdings (C.8.8)
    to_execute = []
    candidates = [p for p in portfolios if any(q > 0 for q in p.holdings.values())]
    for p in rng.sample(candidates, min(args.executed, len(candidates))):
        held = [t for t, q in p.holdings.items() if q > 0]
        if rng.random() < 0.5:
            ticker = rng.choice(held)
            target = money(float(history[ticker][last_day].close) * 1.01)
            qty = rng.randint(1, p.holdings[ticker])
            p.holdings[ticker] -= qty
            cash[p.user_id] += money(qty * target)
            kind = "sell"
        else:
            ticker = rng.choice(tradeable)
            target = money(float(history[ticker][last_day].close) * 0.99)
            qty = min(rng.randint(1, 10), int(cash[p.user_id] / target))
            if qty < 1:
                continue
            p.holdings[ticker] = p.holdings.get(ticker, 0) + qty
            cash[p.user_id] -= money(qty * target)
            kind = "buy"
        add_order(p, ticker, kind, target, qty, "pending")
        to_execute.append(orders[-1][0])

    assert all(c >= 0 for c in cash.values())  # C.1.5
    return Seed(days, history, users, portfolios, transactions, watchlist, orders, to_execute, cash)


def command(args) -> str:
    """The CLI command that reproduces this output."""
    return (f"py tools/generate_seed.py --seed {args.seed} --users {args.users} --days {args.days} "
            f"--end-date {args.end_date} --trades {args.trades} --max-portfolios {args.max_portfolios} "
            f"--max-watch {args.max_watch} --max-orders {args.max_orders} --executed {args.executed}")


def render_sections(seed: Seed, args) -> list:
    """The seed file as (table, sql) pairs, in load order."""
    first_day, last_day = seed.days[0], seed.days[-1]
    s = seed
    sections = [
        ("header",
         f"-- Generated by tools/generate_seed.py; do not edit by hand.\n"
         f"--   {command(args)}\n"
         f"-- {len(s.users)} users, {len(s.portfolios)} portfolios, {len(STOCKS)} stocks, "
         f"{len(s.days) * len(STOCKS)} price rows, {len(s.transactions)} trades, "
         f"{len(s.watchlist)} watchlist rows, {len(s.orders)} limit orders ({len(s.to_execute)} executed on load)\n"
         f"-- Load after sql/ddl.sql. Rows are in time order: the triggers check each\n"
         f"-- trade against the cash and holdings of the rows before it.\n\n"
         "USE stock_trading;\n"),
        ("exchange", section("exchange")
         + insert("exchange", ["exchange_code", "exchange_name", "country", "currency"], EXCHANGES)),
        ("stock", section("stock")
         + insert("stock", ["ticker", "company_name", "sector", "exchange_code"], [x[:4] for x in STOCKS])),
        ("stock_price_history", section(f"stock_price_history ({first_day} to {last_day}, trading days only)")
         + insert("stock_price_history",
                  ["ticker", "price_date", "opening_price", "closing_price", "high_price", "low_price", "volume"],
                  [(t, d, b.open, b.close, b.high, b.low, b.volume)
                   for t, bars in s.history.items() for d, b in bars.items()])),
        ("user", section(f"user (cash_balance starts at the {STARTING_CASH} default; trades update it)")
         + insert("user", ["user_id", "name", "email"], s.users)),
        ("portfolio", section("portfolio")
         + insert("portfolio", ["portfolio_id", "user_id", "portfolio_name", "created_at"],
                  [(p.portfolio_id, p.user_id, p.name, p.created_at) for p in s.portfolios])),
        ("watchlist", section("watchlist")
         + insert("watchlist", ["user_id", "ticker", "target_price", "added_at"], s.watchlist)),
        ("transaction", section("transaction (ids in time order)")
         + insert("transaction",
                  ["transaction_id", "portfolio_id", "ticker", "transaction_type", "quantity", "price", "executed_at"],
                  s.transactions)),
        ("limit_order", section("limit_order")
         + insert("limit_order",
                  ["order_id", "portfolio_id", "ticker", "order_type", "target_price", "quantity", "status", "created_at"],
                  s.orders)),
    ]
    if s.to_execute:
        ids = ", ".join(map(str, s.to_execute))
        sections.append(("execute", section("execute limit orders (trigger inserts the matching transactions)")
                         # ORDER BY: cash was simulated in this order, and buys share a user's cash
                         + f"UPDATE `limit_order` SET `status` = 'executed' WHERE `order_id` IN ({ids}) ORDER BY `order_id`;\n"))
    return sections


def render(seed: Seed, args) -> str:
    return "\n".join(sql for _, sql in render_sections(seed, args))


def generate(args) -> str:
    return render(build(args), args)


def validate(args) -> list:
    """Problems with the options, as messages; empty if they are usable."""
    max_users = len(FIRST_NAMES) * len(LAST_NAMES)
    errors = []
    if args.end_date > date.today():
        errors.append("--end-date can't be in the future: the triggers reject future dates (C.5.7, C.7.10)")
    if not 1 <= args.users <= max_users:
        errors.append(f"--users must be between 1 and {max_users}")
    if args.days < 1:
        errors.append("--days must be at least 1")
    if args.trades < 0:
        errors.append("--trades can't be negative")
    if not 1 <= args.max_portfolios <= len(PORTFOLIO_NAMES):
        errors.append(f"--max-portfolios must be between 1 and {len(PORTFOLIO_NAMES)}")
    if not 0 <= args.max_watch <= len(STOCKS):
        errors.append(f"--max-watch must be between 0 and {len(STOCKS)}")
    if args.max_orders < 0:
        errors.append("--max-orders can't be negative")
    if args.executed < 0:
        errors.append("--executed can't be negative")
    return errors


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Generate seed data for the stock_trading schema.")
    parser.add_argument("--tui", action="store_true",
                        help="open an interactive editor with a live preview (needs: pip install -r tools/requirements.txt)")
    parser.add_argument("-o", "--output", default=str(REPO_ROOT / "sql" / "seed.sql"),
                        help="output file, or - for stdout (default: sql/seed.sql)")
    parser.add_argument("--seed", type=int, default=370, help="random seed (default: 370)")
    parser.add_argument("--users", type=int, default=12, help="number of users (default: 12)")
    parser.add_argument("--days", type=int, default=60, help="trading days of price history (default: 60)")
    parser.add_argument("--end-date", type=date.fromisoformat, default=date(2026, 9, 30),
                        help="last price/trade date, YYYY-MM-DD (default: 2026-09-30)")
    parser.add_argument("--trades", type=int, default=8, help="average trades per portfolio (default: 8)")
    parser.add_argument("--max-portfolios", type=int, default=3, help="max portfolios per user (default: 3)")
    parser.add_argument("--max-watch", type=int, default=5, help="max watchlist entries per user (default: 5)")
    parser.add_argument("--max-orders", type=int, default=2, help="max open/cancelled orders per portfolio (default: 2)")
    parser.add_argument("--executed", type=int, default=3, help="limit orders executed on load (default: 3)")
    args = parser.parse_args(argv)
    # The TUI shows problems inline, so it starts even from bad options
    if not args.tui:
        for error in validate(args):
            parser.error(error)
    return args


def write_sql(path: Path, sql: str) -> None:
    """Write with \\n line endings on every OS (Path.write_text has no newline= before 3.10)."""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(sql)


def main(argv=None):
    args = parse_args(argv)
    if args.tui:
        try:
            from seed_tui import run
        except ImportError as e:
            sys.exit(f"--tui needs Textual ({e}). Install it with: pip install -r tools/requirements.txt")
        run(args)
        return
    sql = generate(args)
    if args.output == "-":
        sys.stdout.reconfigure(newline="\n")  # Windows would otherwise write \r\n
        sys.stdout.write(sql)
    else:
        write_sql(Path(args.output), sql)
        print(f"Wrote {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
