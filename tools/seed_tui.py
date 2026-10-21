"""Interactive editor for generate_seed.py, opened with --tui.

Edit the options on the left; the right side regenerates the seed in the
background and shows row counts, activity and a preview of the SQL. Press
Ctrl+S to write the file.
"""

import argparse
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from statistics import median

from rich.syntax import Syntax
from textual import on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.validation import Function, Integer
from textual.widgets import (Button, DataTable, Footer, Header, Input, Label, Select, Sparkline, Static,
                             TabbedContent, TabPane)
from textual.worker import get_current_worker

import generate_seed as gen

PREVIEW_LINES = 80
SECTIONS = ["header", "exchange", "stock", "stock_price_history", "user", "portfolio",
            "watchlist", "transaction", "limit_order", "execute"]


def is_date(value: str) -> bool:
    try:
        date.fromisoformat(value)
        return True
    except ValueError:
        return False


# (option, label, hint, validator)
FIELDS = [
    ("seed", "Random seed", "Same options + seed = identical file", Integer()),
    ("users", "Users", "Rows in user", Integer(1, len(gen.FIRST_NAMES) * len(gen.LAST_NAMES))),
    ("days", "Trading days", f"Price rows = days x {len(gen.STOCKS)} stocks", Integer(1)),
    ("end_date", "End date", "YYYY-MM-DD; not in the future (C.5.7, C.7.10)",
     Function(lambda v: is_date(v) and date.fromisoformat(v) <= date.today(), "Not a past date")),
    ("trades", "Avg trades / portfolio", "Each portfolio makes 0 to 2x this", Integer(0)),
    ("max_portfolios", "Max portfolios / user", f"1 to {len(gen.PORTFOLIO_NAMES)}", Integer(1, len(gen.PORTFOLIO_NAMES))),
    ("max_watch", "Max watchlist / user", f"0 to {len(gen.STOCKS)}", Integer(0, len(gen.STOCKS))),
    ("max_orders", "Max open orders / portfolio", "Pending or cancelled limit orders", Integer(0)),
    ("executed", "Orders executed on load", "Trigger creates their trades (C.8.7)", Integer(0)),
    ("output", "Output file", "Written on Ctrl+S", None),
]


@dataclass
class Preview:
    args: argparse.Namespace
    seed: gen.Seed
    sections: dict
    size: int


def fmt_size(n: int) -> str:
    return f"{n / 1024:,.1f} KB" if n < 1024 * 1024 else f"{n / 1024 / 1024:,.2f} MB"


def money(d) -> str:
    return f"${d:,.0f}"


class SeedApp(App):
    TITLE = "PaperTrade Seed Generator"
    SUB_TITLE = "sample data for sql/ddl.sql"

    CSS = """
    #body { height: 1fr; }

    #form {
        width: 44;
        padding: 0 1;
        border: round $primary;
        border-title-color: $accent;
        border-title-style: bold;
    }
    .field-label { text-style: bold; color: $accent; }
    .field-label.first { margin-top: 1; }
    .hint { color: $text-muted; text-style: italic; }
    #form Input {
        height: 1;
        border: none;
        padding: 0 1;
        background: $boost;
    }
    #form Input:focus { background: $primary 30%; }
    #form Input.-invalid { background: $error 25%; }
    #errors { color: $error; margin-top: 1; height: auto; }
    #buttons { height: auto; margin: 1 0; }
    #buttons Button { margin-right: 1; }

    #main { width: 1fr; padding: 0 0 0 1; }

    #cards { height: 5; }
    .card {
        width: 1fr;
        height: 5;
        border: round $secondary;
        margin-right: 1;
    }
    .card-value { width: 1fr; content-align: center middle; text-style: bold; color: $accent; height: 2; padding-top: 1; }
    .card-label { width: 1fr; content-align: center middle; color: $text-muted; }

    TabbedContent { height: 1fr; }
    DataTable { height: auto; max-height: 12; }
    .spark-label { margin-top: 1; text-style: bold; }
    Sparkline { height: 4; margin: 0 1; }
    #activity-stats { margin-top: 1; color: $text-muted; }
    #sql-select { width: 40; margin-bottom: 1; }
    #sql-scroll { height: 1fr; border: round $panel; }

    #command {
        height: auto;
        border: round $success;
        border-title-color: $success;
        padding: 0 1;
        color: $text-muted;
    }
    #status { height: 1; color: $text-muted; padding-left: 1; }
    """

    BINDINGS = [
        Binding("ctrl+s", "write", "Write file", priority=True),
        Binding("ctrl+r", "reset", "Reset", priority=True),
        Binding("ctrl+q", "quit", "Quit", priority=True),
    ]

    def __init__(self, initial: argparse.Namespace):
        super().__init__()
        self.initial = initial
        self.preview = None
        self._debounce = None

    # ----------------------------------------------------- layout
    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal(id="body"):
            with VerticalScroll(id="form") as form:
                form.border_title = "Parameters"
                for i, (name, label, hint, validator) in enumerate(FIELDS):
                    yield Label(label, classes="field-label first" if i == 0 else "field-label")
                    yield Input(self._initial_value(name), id=f"f-{name}",
                                validators=[validator] if validator else [], validate_on=["changed"])
                    yield Static(hint, classes="hint")
                yield Static(id="errors")
                with Horizontal(id="buttons"):
                    yield Button("Write file", id="write", variant="success")
                    yield Button("Reset", id="reset")
            with Vertical(id="main"):
                with Horizontal(id="cards"):
                    for key, label in [("rows", "total rows"), ("size", "seed.sql size"),
                                       ("trades", "buys / sells"), ("cash", "final cash, median")]:
                        with Vertical(classes="card"):
                            yield Static("-", id=f"card-{key}", classes="card-value")
                            yield Static(label, classes="card-label")
                with TabbedContent():
                    with TabPane("Overview", id="tab-overview"):
                        with VerticalScroll():
                            yield DataTable(id="tables", zebra_stripes=True, cursor_type="row")
                            yield Label("Trades per trading day", classes="spark-label")
                            yield Sparkline([0], id="spark-trades", summary_function=max)
                            yield Label("Final cash per user", classes="spark-label")
                            yield Sparkline([0], id="spark-cash", summary_function=max)
                            yield Label("Average closing price, all stocks", classes="spark-label")
                            yield Sparkline([0], id="spark-price", summary_function=max)
                            yield Static(id="activity-stats")
                    with TabPane("SQL preview", id="tab-sql"):
                        yield Select([(s, s) for s in SECTIONS], value="header", allow_blank=False, id="sql-select")
                        with VerticalScroll(id="sql-scroll"):
                            yield Static(id="sql")
                command = Static(id="command", markup=False)
                command.border_title = "Equivalent command"
                yield command
                yield Static(id="status")
        yield Footer()

    def on_mount(self) -> None:
        if "tokyo-night" in self.available_themes:
            self.theme = "tokyo-night"
        table = self.query_one("#tables", DataTable)
        table.add_columns("Table", "Rows", "Details")
        self.refresh_preview()

    def _initial_value(self, name: str) -> str:
        value = getattr(self.initial, name)
        if name != "output":
            return str(value)
        if value in (None, "-"):
            return "sql/seed.sql"
        try:  # show the default repo path as sql/seed.sql rather than in full
            return Path(value).resolve().relative_to(Path.cwd()).as_posix()
        except ValueError:
            return value

    # ----------------------------------------------------- reading the form
    def read_args(self):
        """The options in the form, and any problems with them."""
        raw = {name: self.query_one(f"#f-{name}", Input).value.strip() for name, *_ in FIELDS}
        values, errors = {}, []
        for name, label, *_ in FIELDS:
            if name == "output":
                values[name] = raw[name]
                if not raw[name] or raw[name] == "-":
                    errors.append("Output file: enter a file path")
            elif name == "end_date":
                if is_date(raw[name]):
                    values[name] = date.fromisoformat(raw[name])
                else:
                    errors.append(f"{label}: use YYYY-MM-DD")
            else:
                try:
                    values[name] = int(raw[name])
                except ValueError:
                    errors.append(f"{label}: enter a whole number")
        args = argparse.Namespace(tui=True, **values)
        if not errors:
            errors = gen.validate(args)
        return args, errors

    # ----------------------------------------------------- live preview
    @on(Input.Changed)
    def _schedule(self) -> None:
        if self._debounce:
            self._debounce.stop()
        self._debounce = self.set_timer(0.25, self.refresh_preview)

    def refresh_preview(self) -> None:
        args, errors = self.read_args()
        self.query_one("#errors", Static).update("\n".join(f"x {e}" for e in errors))
        self.query_one("#write", Button).disabled = bool(errors)
        if errors:
            self.query_one("#status", Static).update("Fix the options above to update the preview")
            return
        self.query_one("#status", Static).update("Generating...")
        self.build_preview(args)

    @work(thread=True, exclusive=True, group="preview")
    def build_preview(self, args) -> None:
        seed = gen.build(args)
        sections = dict(gen.render_sections(seed, args))
        size = len("\n".join(sections.values()).encode("utf-8"))
        if not get_current_worker().is_cancelled:
            self.call_from_thread(self.show_preview, Preview(args, seed, sections, size))

    def show_preview(self, p: Preview) -> None:
        self.preview = p
        s = p.seed
        buys = sum(1 for t in s.transactions if t[3] == "buy")
        sells = len(s.transactions) - buys
        price_rows = len(s.days) * len(gen.STOCKS)
        orders = {status: sum(1 for o in s.orders if o[6] == status) for status in ("pending", "cancelled")}
        targets = sum(1 for w in s.watchlist if w[2] is not None)
        cash = sorted(s.cash.values())
        total_rows = (len(gen.EXCHANGES) + len(gen.STOCKS) + price_rows + len(s.users) + len(s.portfolios)
                      + len(s.watchlist) + len(s.transactions) + len(s.to_execute) + len(s.orders))

        self.query_one("#card-rows", Static).update(f"{total_rows:,}")
        self.query_one("#card-size", Static).update(fmt_size(p.size))
        self.query_one("#card-trades", Static).update(f"{buys:,} / {sells:,}")
        self.query_one("#card-cash", Static).update(money(median(cash)))

        first, last = s.days[0], s.days[-1]
        trade_span = (f"{s.transactions[0][6]:%Y-%m-%d} to {s.transactions[-1][6]:%Y-%m-%d}"
                      if s.transactions else "no trades")
        rows = [
            ("exchange", len(gen.EXCHANGES), "NASDAQ, NYSE, TSX (fixed)"),
            ("stock", len(gen.STOCKS), "Fixed list; TSX stocks are watch-only (one cash currency)"),
            ("stock_price_history", price_rows, f"{len(s.days)} days x {len(gen.STOCKS)} stocks, {first} to {last}"),
            ("user", len(s.users), f"Start {money(gen.STARTING_CASH)}; final {money(cash[0])} to {money(cash[-1])}"),
            ("portfolio", len(s.portfolios), f"{len(s.portfolios) / len(s.users):.1f} per user on average"),
            ("watchlist", len(s.watchlist), f"{targets} with a target price, {len(s.watchlist) - targets} NULL"),
            ("transaction", len(s.transactions) + len(s.to_execute),
             f"{buys} buys, {sells} sells, {trade_span}; +{len(s.to_execute)} from executed orders"),
            ("limit_order", len(s.orders),
             f"{orders['pending']} pending, {orders['cancelled']} cancelled, {len(s.to_execute)} executed on load"),
        ]
        table = self.query_one("#tables", DataTable)
        table.clear()
        for name, count, details in rows:
            table.add_row(name, f"{count:,}", details)

        per_day = {d: 0 for d in s.days}
        for t in s.transactions:
            per_day[t[6].date()] += 1
        avg_close = [float(sum(s.history[t][d].close for t in s.history)) / len(s.history) for d in s.days]
        self.query_one("#spark-trades", Sparkline).data = list(per_day.values()) or [0]
        self.query_one("#spark-cash", Sparkline).data = [float(c) for c in cash] or [0]
        self.query_one("#spark-price", Sparkline).data = avg_close or [0]
        busiest = max(per_day, key=per_day.get)
        self.query_one("#activity-stats", Static).update(
            f"Busiest day: {busiest} ({per_day[busiest]} trades)\n"
            f"Users with no trades: {sum(1 for c in s.cash.values() if c == gen.STARTING_CASH)}\n"
            f"Cash spent across all users: {money(gen.STARTING_CASH * len(s.users) - sum(cash))}"
        )

        self.query_one("#command", Static).update(gen.command(p.args) + f" -o {p.args.output}")
        lines = sum(v.count("\n") for v in p.sections.values())
        self.query_one("#status", Static).update(f"Preview up to date: {lines:,} lines")
        self.show_sql()

    @on(Select.Changed, "#sql-select")
    def show_sql(self) -> None:
        if not self.preview:
            return
        name = self.query_one("#sql-select", Select).value
        text = self.preview.sections.get(name, "-- (nothing for this table with these options)\n")
        lines = text.rstrip("\n").split("\n")
        if len(lines) > PREVIEW_LINES:
            lines = lines[:PREVIEW_LINES] + [f"-- ... {len(lines) - PREVIEW_LINES:,} more lines"]
        self.query_one("#sql", Static).update(
            Syntax("\n".join(lines), "sql", theme="monokai", line_numbers=True, word_wrap=False,
                   background_color=self.current_theme.surface or "default"))

    # ----------------------------------------------------- actions
    @on(Button.Pressed, "#write")
    def action_write(self) -> None:
        args, errors = self.read_args()
        if errors:
            self.notify("\n".join(errors), title="Can't write yet", severity="error")
            return
        path = Path(args.output)
        try:
            sql = gen.generate(args)
            path.parent.mkdir(parents=True, exist_ok=True)
            gen.write_sql(path, sql)
        except OSError as e:
            self.notify(str(e), title="Write failed", severity="error")
            return
        self.notify(f"{path} ({fmt_size(len(sql.encode('utf-8')))}). Reload with: docker compose down -v",
                    title="Seed written")

    @on(Button.Pressed, "#reset")
    def action_reset(self) -> None:
        for name, *_ in FIELDS:
            self.query_one(f"#f-{name}", Input).value = self._initial_value(name)
        self.notify("Options reset")


def run(args: argparse.Namespace) -> None:
    SeedApp(args).run()
