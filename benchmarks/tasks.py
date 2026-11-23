"""Tareas reproducibles de benchmark con verificadores deterministas.

Cada tarea genera un repositorio limpio dentro de un directorio temporal y
verifica el resultado objetivamente sin depender de la declaración del modelo.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


@dataclass(frozen=True)
class BenchmarkTask:
    task_id: str
    title: str
    suite: str  # "quick" (incluida también en "full") o "full"
    category: str
    prompts: tuple[str, ...]
    setup: Callable[[Path], dict]
    verify: Callable[[Path, list[str], dict], dict]
    description: str


def _write_files(root: Path, files: dict[str, str]) -> None:
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")


def _tree_hashes(root: Path) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            rel = str(path.relative_to(root))
            hashes[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def _run_python(workspace: Path, code: str, timeout: int = 20) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-c", code],
        cwd=workspace,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _run_unittest(workspace: Path, timeout: int = 25) -> tuple[bool, int, str]:
    proc = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"],
        cwd=workspace,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    combined = (proc.stdout + "\n" + proc.stderr).strip()
    count = 0
    for line in combined.splitlines():
        if line.startswith("Ran ") and " test" in line:
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                count = int(parts[1])
    return proc.returncode == 0, count, combined[-1200:]


# ---------------------------------------------------------------------------
# T1: Inspección de solo lectura multi-archivo + log con ruido
# ---------------------------------------------------------------------------

def _setup_t1(workspace: Path) -> dict:
    noise_lines = [
        f"2026-10-15T10:{i // 60:02d}:{i % 60:02d}Z INFO worker={i % 4} "
        f"order=ORD-{100 + i} stage=validate latency_ms={12 + (i % 19)} status=ok"
        for i in range(620)
    ]
    noise_lines.insert(
        341,
        "2026-10-15T10:05:41Z ERROR worker=2 order=ORD-42 code=ERR-PRICING-402 "
        "msg=\"order total mismatch: expected=90.00 actual=88.00 module=app/pricing.py\"",
    )
    files = {
        "AGENTS.md": """
            # Billing Mini-App
            - Code lives in `app/`. Logs live in `logs/`.
            - Use targeted searches (`rg`) and bounded reads; do not dump full logs.
        """,
        "README.md": """
            # Billing Mini-App
            Computes order totals with discounts and tax.
        """,
        "app/__init__.py": "",
        "app/config.py": """
            DEFAULT_TAX_RATE = 0.10
            CURRENCY = "USD"
        """,
        "app/discounts.py": """
            COUPONS = {"SAVE20": 20.0, "SAVE10": 10.0}

            def coupon_amount(code: str | None) -> float:
                if not code:
                    return 0.0
                return COUPONS.get(code, 0.0)
        """,
        "app/tax.py": """
            def apply_tax(amount: float, rate: float) -> float:
                return round(amount * (1.0 + rate), 2)
        """,
        "app/pricing.py": """
            from .config import DEFAULT_TAX_RATE
            from .discounts import coupon_amount
            from .tax import apply_tax

            def calculate_order_total(subtotal: float, coupon: str | None = None,
                                      tax_rate: float = DEFAULT_TAX_RATE) -> float:
                # BUG: tax is applied BEFORE subtracting the coupon discount.
                # Policy requires subtracting the discount first (clamped at 0),
                # then applying tax to the discounted subtotal.
                taxed = apply_tax(subtotal, tax_rate)
                discount = coupon_amount(coupon)
                return round(max(0.0, taxed - discount), 2)
        """,
        "app/orders.py": """
            from .pricing import calculate_order_total

            SAMPLE_ORDERS = {
                "ORD-42": {"subtotal": 100.0, "coupon": "SAVE20", "tax_rate": 0.10},
            }

            def total_for(order_id: str) -> float:
                order = SAMPLE_ORDERS[order_id]
                return calculate_order_total(order["subtotal"], order["coupon"], order["tax_rate"])
        """,
        "logs/build.log": "\n".join(noise_lines) + "\n",
    }
    _write_files(workspace, files)
    return {"hashes": _tree_hashes(workspace)}


def _verify_t1(workspace: Path, final_texts: list[str], baseline: dict) -> dict:
    answer = "\n".join(final_texts).lower()
    unchanged = _tree_hashes(workspace) == baseline["hashes"]
    mentions_file = "pricing.py" in answer
    mentions_func = "calculate_order_total" in answer
    mentions_code = "err-pricing-402" in answer
    mentions_order = ("tax" in answer or "impuesto" in answer) and (
        "discount" in answer or "descuento" in answer or "cupón" in answer or "cupon" in answer
    )
    checks = [
        {"name": "workspace_unchanged", "passed": unchanged},
        {"name": "identifies_pricing_file", "passed": mentions_file},
        {"name": "identifies_function", "passed": mentions_func},
        {"name": "identifies_log_error_code", "passed": mentions_code},
        {"name": "explains_tax_discount_order", "passed": mentions_order},
    ]
    passed = all(c["passed"] for c in checks)
    return {"passed": passed, "checks": checks, "summary": "ok" if passed else "falló verificación"}


# ---------------------------------------------------------------------------
# T2: Bugfix puntual + test de regresión
# ---------------------------------------------------------------------------

def _setup_t2(workspace: Path) -> dict:
    files = {
        "AGENTS.md": """
            # Retry Budget
            - Run tests with: `python3 -m unittest discover -s tests -v`
            - Source: `retry_budget.py`. Tests: `tests/test_retry_budget.py`.
        """,
        "retry_budget.py": """
            \"\"\"Retry backoff and attempt budget utilities.\"\"\"

            def can_retry(attempt: int, max_attempts: int) -> bool:
                \"\"\"Return True if another retry is allowed after `attempt` failures (1-indexed).\"\"\"
                if max_attempts < 1:
                    return False
                # BUG: allows one extra attempt (should be attempt < max_attempts)
                return attempt <= max_attempts

            def compute_delay(retry_index: int, base_delay: float = 0.5,
                              max_delay: float = 10.0) -> float:
                \"\"\"Exponential backoff delay for 0-indexed retry, capped at max_delay.\"\"\"
                if retry_index < 0:
                    raise ValueError("retry_index must be >= 0")
                if base_delay < 0 or max_delay < 0:
                    raise ValueError("delays must be non-negative")
                delay = base_delay * (2 ** retry_index)
                # BUG: forgets to cap when retry_index == 0 (if base_delay > max_delay)
                if retry_index > 0 and delay > max_delay:
                    return max_delay
                return delay
        """,
        "tests/__init__.py": "",
        "tests/test_retry_budget.py": """
            import unittest
            from retry_budget import can_retry, compute_delay

            class RetryBudgetTests(unittest.TestCase):
                def test_can_retry_allows_first_retry(self):
                    self.assertTrue(can_retry(1, 3))

                def test_can_retry_zero_max_attempts(self):
                    self.assertFalse(can_retry(1, 0))

                def test_compute_delay_exponential(self):
                    self.assertEqual(compute_delay(0, base_delay=0.5, max_delay=10.0), 0.5)
                    self.assertEqual(compute_delay(2, base_delay=0.5, max_delay=10.0), 2.0)

                def test_compute_delay_caps_large_retry(self):
                    self.assertEqual(compute_delay(6, base_delay=0.5, max_delay=10.0), 10.0)
        """,
    }
    _write_files(workspace, files)
    return {"initial_tests": 4}


def _verify_t2(workspace: Path, _final_texts: list[str], baseline: dict) -> dict:
    ok_suite, count, tail = _run_unittest(workspace)
    hidden = _run_python(
        workspace,
        """
import retry_budget as rb
assert rb.can_retry(1, 3) is True
assert rb.can_retry(2, 3) is True
assert rb.can_retry(3, 3) is False
assert rb.can_retry(1, 1) is False
assert rb.can_retry(1, 0) is False
assert rb.compute_delay(0, base_delay=15.0, max_delay=10.0) == 10.0
assert rb.compute_delay(0, base_delay=0.5, max_delay=10.0) == 0.5
assert rb.compute_delay(5, base_delay=1.0, max_delay=10.0) == 10.0
print("HIDDEN_OK")
""",
    )
    checks = [
        {"name": "unittest_passes", "passed": ok_suite, "detail": tail if not ok_suite else ""},
        {"name": "regression_tests_added", "passed": count >= baseline["initial_tests"] + 1,
         "detail": f"tests={count}"},
        {"name": "hidden_assertions", "passed": hidden.returncode == 0 and "HIDDEN_OK" in hidden.stdout,
         "detail": hidden.stderr.strip()[-400:]},
    ]
    passed = all(c["passed"] for c in checks)
    return {"passed": passed, "checks": checks, "summary": "ok" if passed else "falló verificación"}


# ---------------------------------------------------------------------------
# T3: Feature multi-archivo + compatibilidad hacia atrás
# ---------------------------------------------------------------------------

def _setup_t3(workspace: Path) -> dict:
    files = {
        "AGENTS.md": """
            # Inventory CLI
            - Run tests: `python3 -m unittest discover -s tests -v`
            - Package: `inventory/` (`models.py`, `store.py`, `cli.py`).
            - Preserve existing JSON output compatibility when `--format` is omitted.
        """,
        "inventory/__init__.py": "",
        "inventory/models.py": """
            from dataclasses import dataclass

            @dataclass(frozen=True)
            class Item:
                sku: str
                name: str
                category: str
                qty: int
        """,
        "inventory/store.py": """
            import json
            from pathlib import Path
            from .models import Item

            def load_items(path: Path) -> list[Item]:
                raw = json.loads(path.read_text(encoding="utf-8"))
                return [Item(row["sku"], row["name"], row["category"], int(row["qty"])) for row in raw]

            def filter_items(items: list[Item], include_zero: bool = False) -> list[Item]:
                if include_zero:
                    return list(items)
                return [item for item in items if item.qty > 0]
        """,
        "inventory/cli.py": """
            import argparse
            import json
            from pathlib import Path
            from .store import filter_items, load_items

            def format_json(items) -> str:
                return json.dumps(
                    [{"sku": i.sku, "name": i.name, "category": i.category, "qty": i.qty} for i in items],
                    ensure_ascii=False,
                )

            def main(argv: list[str] | None = None) -> int:
                parser = argparse.ArgumentParser(prog="inventory")
                parser.add_argument("data_file", type=Path)
                parser.add_argument("--include-zero", action="store_true")
                args = parser.parse_args(argv)
                items = filter_items(load_items(args.data_file), include_zero=args.include_zero)
                print(format_json(items))
                return 0
        """,
        "tests/__init__.py": "",
        "tests/test_inventory.py": """
            import io
            import json
            import tempfile
            import unittest
            from contextlib import redirect_stdout
            from pathlib import Path
            from inventory.cli import main

            SAMPLE = [
                {"sku": "A1", "name": "Keyboard", "category": "hardware", "qty": 4},
                {"sku": "A2", "name": "Mouse, Wireless", "category": "hardware", "qty": 0},
                {"sku": "B1", "name": "Arch Guide", "category": "books", "qty": 2},
            ]

            class InventoryTests(unittest.TestCase):
                def _write_sample(self, directory: str) -> Path:
                    path = Path(directory) / "items.json"
                    path.write_text(json.dumps(SAMPLE), encoding="utf-8")
                    return path

                def test_default_json_excludes_zero_qty(self):
                    with tempfile.TemporaryDirectory() as tmp:
                        path = self._write_sample(tmp)
                        buf = io.StringIO()
                        with redirect_stdout(buf):
                            code = main([str(path)])
                        self.assertEqual(code, 0)
                        rows = json.loads(buf.getvalue())
                        self.assertEqual([r["sku"] for r in rows], ["A1", "B1"])
        """,
    }
    _write_files(workspace, files)
    return {"initial_tests": 1}


def _verify_t3(workspace: Path, _final_texts: list[str], baseline: dict) -> dict:
    ok_suite, count, tail = _run_unittest(workspace)
    hidden = _run_python(
        workspace,
        """
import csv, io, json, tempfile
from contextlib import redirect_stdout
from pathlib import Path
from inventory.cli import main
from inventory.store import filter_items, load_items

SAMPLE = [
    {"sku": "A1", "name": "Keyboard", "category": "hardware", "qty": 4},
    {"sku": "A2", "name": "Mouse, Wireless", "category": "hardware", "qty": 0},
    {"sku": "B1", "name": "Arch Guide", "category": "books", "qty": 2},
]
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / "items.json"
    p.write_text(json.dumps(SAMPLE), encoding="utf-8")
    # Default JSON backwards compatibility
    out = io.StringIO()
    with redirect_stdout(out):
        assert main([str(p)]) == 0
    assert [r["sku"] for r in json.loads(out.getvalue())] == ["A1", "B1"]

    # Category filter + include-zero + CSV format with comma escaping
    out = io.StringIO()
    with redirect_stdout(out):
        assert main([str(p), "--category", "hardware", "--include-zero", "--format", "csv"]) == 0
    rows = list(csv.DictReader(io.StringIO(out.getvalue())))
    assert len(rows) == 2
    assert rows[0]["sku"] == "A1" and rows[0]["qty"] == "4"
    assert rows[1]["sku"] == "A2" and rows[1]["name"] == "Mouse, Wireless" and rows[1]["qty"] == "0"

    # Store filter_items signature supports category
    items = load_items(p)
    books = filter_items(items, include_zero=False, category="books")
    assert [i.sku for i in books] == ["B1"]
print("HIDDEN_OK")
""",
    )
    checks = [
        {"name": "unittest_passes", "passed": ok_suite, "detail": tail if not ok_suite else ""},
        {"name": "new_tests_added", "passed": count >= baseline["initial_tests"] + 2,
         "detail": f"tests={count}"},
        {"name": "hidden_acceptance", "passed": hidden.returncode == 0 and "HIDDEN_OK" in hidden.stdout,
         "detail": hidden.stderr.strip()[-400:]},
    ]
    passed = all(c["passed"] for c in checks)
    return {"passed": passed, "checks": checks, "summary": "ok" if passed else "falló verificación"}


# ---------------------------------------------------------------------------
# T4: Debug de suite con salida larga, ruidosa y códigos ANSI
# ---------------------------------------------------------------------------

def _setup_t4(workspace: Path) -> dict:
    files = {
        "AGENTS.md": """
            # Log Parser
            - Run tests: `python3 -m unittest discover -s tests -v`
            - Notice tests emit verbose diagnostics; save logs or filter output if truncated.
            - Source: `logparser/parser.py`. Tests: `tests/test_parser.py`.
        """,
        "logparser/__init__.py": "",
        "logparser/parser.py": """
            import re

            def parse_duration(spec: str) -> int:
                \"\"\"Parse duration strings like '30s', '2m', '1h30m', '1h2m5s' into seconds.\"\"\"
                text = spec.strip()
                if not text:
                    raise ValueError("empty duration")
                # BUG 1: only parses a single unit like '30s' or '2m', fails on compound '1h30m'
                match = re.fullmatch(r"(\\d+)([hms])", text)
                if not match:
                    raise ValueError(f"invalid duration: {spec}")
                value, unit = int(match.group(1)), match.group(2)
                return value * {"h": 3600, "m": 60, "s": 1}[unit]

            def parse_kv_line(line: str) -> dict[str, str]:
                \"\"\"Parse whitespace-separated key=value tokens; values may contain '='.\"\"\"
                result: dict[str, str] = {}
                for token in line.strip().split():
                    if "=" not in token:
                        raise ValueError(f"invalid token: {token}")
                    # BUG 2: splits on all '=' instead of maxsplit=1
                    parts = token.split("=")
                    if len(parts) != 2 or not parts[0]:
                        raise ValueError(f"invalid token: {token}")
                    result[parts[0]] = parts[1]
                return result
        """,
        "tests/__init__.py": "",
        "tests/test_parser.py": """
            import unittest
            from logparser.parser import parse_duration, parse_kv_line

            def _emit_noise(label: str) -> None:
                for idx in range(45):
                    print(
                        f"\\x1b[32m[TRACE]\\x1b[0m \\x1b[33m{label}\\x1b[0m "
                        f"chunk={idx:02d} metric=ok payload={'x' * 40}"
                    )

            class ParserTests(unittest.TestCase):
                def test_01_simple_seconds(self):
                    _emit_noise("simple_seconds")
                    self.assertEqual(parse_duration("45s"), 45)

                def test_02_simple_minutes(self):
                    _emit_noise("simple_minutes")
                    self.assertEqual(parse_duration("3m"), 180)

                def test_03_compound_duration(self):
                    _emit_noise("compound_duration")
                    self.assertEqual(parse_duration("1h30m"), 5400)
                    self.assertEqual(parse_duration("1h2m5s"), 3725)

                def test_04_kv_basic(self):
                    _emit_noise("kv_basic")
                    self.assertEqual(parse_kv_line("host=arch status=200"), {"host": "arch", "status": "200"})

                def test_05_kv_value_with_equals(self):
                    _emit_noise("kv_equals")
                    self.assertEqual(
                        parse_kv_line("url=https://a.test?x=1&y=2 token=abc=="),
                        {"url": "https://a.test?x=1&y=2", "token": "abc=="},
                    )

                def test_06_invalid_rejected(self):
                    _emit_noise("invalid_rejected")
                    with self.assertRaises(ValueError):
                        parse_duration("abc")
                    with self.assertRaises(ValueError):
                        parse_kv_line("broken")
        """,
    }
    _write_files(workspace, files)
    return {"initial_tests": 6}


def _verify_t4(workspace: Path, _final_texts: list[str], baseline: dict) -> dict:
    ok_suite, count, tail = _run_unittest(workspace)
    hidden = _run_python(
        workspace,
        """
from logparser.parser import parse_duration, parse_kv_line
assert parse_duration("45s") == 45
assert parse_duration("1h30m") == 5400
assert parse_duration("2h0m10s") == 7210
assert parse_duration("5m30s") == 330
for bad in ("", "abc", "10d", "30s10m", "10s10s"):
    try:
        parse_duration(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"should fail: {bad}")
assert parse_kv_line("a=1 b=2=3 c=d==") == {"a": "1", "b": "2=3", "c": "d=="}
try:
    parse_kv_line("=noval")
except ValueError:
    pass
else:
    raise AssertionError("empty key should fail")
print("HIDDEN_OK")
""",
    )
    checks = [
        {"name": "unittest_passes", "passed": ok_suite, "detail": tail if not ok_suite else ""},
        {"name": "tests_preserved", "passed": count >= baseline["initial_tests"],
         "detail": f"tests={count}"},
        {"name": "hidden_assertions", "passed": hidden.returncode == 0 and "HIDDEN_OK" in hidden.stdout,
         "detail": hidden.stderr.strip()[-400:]},
    ]
    passed = all(c["passed"] for c in checks)
    return {"passed": passed, "checks": checks, "summary": "ok" if passed else "falló verificación"}


# ---------------------------------------------------------------------------
# T5: Sesión multi-turno en el mismo chat (estrés de caché y contexto)
# ---------------------------------------------------------------------------

def _setup_t5(workspace: Path) -> dict:
    files = {
        "AGENTS.md": """
            # Mini Ledger
            - Run tests: `python3 -m unittest discover -s tests -v`
            - Package: `ledger/account.py`, `ledger/report.py`, `tests/test_ledger.py`.
        """,
        "ledger/__init__.py": "",
        "ledger/account.py": """
            from dataclasses import dataclass

            @dataclass
            class Account:
                name: str
                balance: int = 0

                def deposit(self, amount: int) -> None:
                    if amount <= 0:
                        raise ValueError("amount must be positive")
                    self.balance += amount

                def withdraw(self, amount: int) -> None:
                    if amount <= 0:
                        raise ValueError("amount must be positive")
                    if amount > self.balance:
                        raise ValueError("insufficient funds")
                    self.balance -= amount
        """,
        "ledger/report.py": """
            def total_balance(accounts) -> int:
                return sum(account.balance for account in accounts)
        """,
        "tests/__init__.py": "",
        "tests/test_ledger.py": """
            import unittest
            from ledger.account import Account
            from ledger.report import total_balance

            class LedgerTests(unittest.TestCase):
                def test_deposit_and_withdraw(self):
                    acc = Account("main", 100)
                    acc.deposit(50)
                    acc.withdraw(30)
                    self.assertEqual(acc.balance, 120)
                    self.assertEqual(total_balance([acc]), 120)
        """,
    }
    _write_files(workspace, files)
    return {"initial_tests": 1}


def _verify_t5(workspace: Path, _final_texts: list[str], baseline: dict) -> dict:
    ok_suite, count, tail = _run_unittest(workspace)
    hidden = _run_python(
        workspace,
        """
from ledger.account import Account, transfer
from ledger.report import summary_by_tag, total_balance

a = Account("checking", 100)
b = Account("savings", 50)
transfer(a, b, 40)
assert a.balance == 60 and b.balance == 90
assert total_balance([a, b]) == 150

for bad_call in (
    lambda: transfer(a, b, 0),
    lambda: transfer(a, b, -5),
    lambda: transfer(a, a, 10),
    lambda: transfer(a, b, 999),
):
    try:
        bad_call()
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError")
assert a.balance == 60 and b.balance == 90

entries = [
    {"tag": "food", "amount": 25},
    {"tag": "books", "amount": 40},
    {"tag": "food", "amount": 15},
]
summary = summary_by_tag(entries)
assert list(summary.items()) == [("books", 40), ("food", 40)]
print("HIDDEN_OK")
""",
    )
    checks = [
        {"name": "unittest_passes", "passed": ok_suite, "detail": tail if not ok_suite else ""},
        {"name": "new_tests_added", "passed": count >= baseline["initial_tests"] + 2,
         "detail": f"tests={count}"},
        {"name": "hidden_assertions", "passed": hidden.returncode == 0 and "HIDDEN_OK" in hidden.stdout,
         "detail": hidden.stderr.strip()[-400:]},
    ]
    passed = all(c["passed"] for c in checks)
    return {"passed": passed, "checks": checks, "summary": "ok" if passed else "falló verificación"}


TASKS: tuple[BenchmarkTask, ...] = (
    BenchmarkTask(
        task_id="t1_inspect_answer",
        title="Inspección multi-archivo y log ruidoso (solo lectura)",
        suite="full",
        category="inspection",
        description="Encuentra causa raíz y código de error en un log de 620 líneas sin editar archivos.",
        prompts=(
            "Investiga por qué la orden ORD-42 calcula mal el total en este proyecto. "
            "No modifiques ningún archivo. Lee AGENTS.md si existe, localiza el archivo y "
            "función con el bug, explica brevemente la causa raíz e incluye el código de "
            "error exacto que aparece en logs/build.log.",
        ),
        setup=_setup_t1,
        verify=_verify_t1,
    ),
    BenchmarkTask(
        task_id="t2_bugfix_single",
        title="Bugfix localizado + test de regresión",
        suite="quick",
        category="bugfix",
        description="Corrige 2 bugs puntuales en retry_budget.py y añade pruebas de regresión.",
        prompts=(
            "Lee AGENTS.md y revisa retry_budget.py y tests/test_retry_budget.py. "
            "Corrige los dos bugs en retry_budget.py: (1) can_retry permite un intento de más "
            "cuando attempt == max_attempts, y (2) compute_delay no aplica max_delay cuando "
            "retry_index == 0 y base_delay > max_delay. Añade tests de regresión, ejecuta "
            "toda la suite hasta que pase y resume el cambio y la comprobación.",
        ),
        setup=_setup_t2,
        verify=_verify_t2,
    ),
    BenchmarkTask(
        task_id="t3_feature_multifile",
        title="Feature multi-archivo (filtro + CSV) con compatibilidad",
        suite="full",
        category="feature",
        description="Añade filtro --category y --format csv en inventory/{store,cli}.py y tests.",
        prompts=(
            "Lee AGENTS.md e implementa estas mejoras en el paquete inventory: "
            "1) En inventory/store.py, añade parámetro opcional `category: str | None = None` a "
            "`filter_items(items, include_zero=False, category=None)` para filtrar por categoría exacta. "
            "2) En inventory/cli.py, añade los flags `--category` y `--format` (`json` por defecto, o `csv` "
            "con cabecera `sku,name,category,qty` usando el módulo estándar `csv` para escapar comas). "
            "Conserva intacta la salida JSON cuando no se pasa `--format`. "
            "3) Añade al menos dos tests nuevos en tests/test_inventory.py cubriendo filtro y CSV, "
            "ejecuta las pruebas y confirma el resultado.",
        ),
        setup=_setup_t3,
        verify=_verify_t3,
    ),
    BenchmarkTask(
        task_id="t4_noisy_test_debug",
        title="Diagnóstico con salida ruidosa y códigos ANSI",
        suite="full",
        category="debugging",
        description="Corrige 2 fallos ocultos entre ~15k caracteres de logs con ANSI en unittest.",
        prompts=(
            "Lee AGENTS.md y ejecuta las pruebas del proyecto. La salida tiene muchos trazos de log; "
            "diagnostica los fallos en logparser/parser.py y corrígelos: parse_duration debe aceptar "
            "duraciones compuestas ordenadas h/m/s (sin unidades repetidas ni invertidas, rechazando vacíos "
            "o unidades inválidas) y parse_kv_line debe permitir '=' dentro de los valores manteniendo "
            "rechazo de claves vacías o tokens sin '='. No elimines pruebas existentes. "
            "Ejecuta toda la suite hasta que pase sin fallos.",
        ),
        setup=_setup_t4,
        verify=_verify_t4,
    ),
    BenchmarkTask(
        task_id="t5_multiturn_session",
        title="Sesión multi-turno en un mismo chat (estrés de caché)",
        suite="quick",
        category="multiturn",
        description="3 mensajes seguidos en la misma conversación midiendo caché inter-turno.",
        prompts=(
            "Lee AGENTS.md e inspecciona los archivos del proyecto. Sin editar nada todavía, "
            "resume brevemente qué módulos existen y qué funciones públicas ofrecen.",
            "Ahora añade una función `transfer(source, target, amount)` en `ledger/account.py` "
            "que rechace con `ValueError` montos <= 0, transferencias a la misma cuenta (`source is target`) "
            "o fondos insuficientes sin alterar saldos en error. Añade tests en `tests/test_ledger.py` "
            "y ejecútalos.",
            "Por último, añade `summary_by_tag(entries)` en `ledger/report.py` que sume `amount` "
            "por cada `tag` devolviendo un dict ordenado alfabéticamente por tag. Añade tests para "
            "`summary_by_tag`, ejecuta toda la suite y confirma el resultado final.",
        ),
        setup=_setup_t5,
        verify=_verify_t5,
    ),
)

TASKS_BY_ID: dict[str, BenchmarkTask] = {task.task_id: task for task in TASKS}


def select_tasks(suite: str = "quick", task_ids: list[str] | None = None) -> list[BenchmarkTask]:
    if task_ids:
        missing = [tid for tid in task_ids if tid not in TASKS_BY_ID]
        if missing:
            raise ValueError(f"Tareas desconocidas: {', '.join(missing)}")
        return [TASKS_BY_ID[tid] for tid in task_ids]
    if suite == "quick":
        return [task for task in TASKS if task.suite == "quick"]
    if suite == "full":
        return list(TASKS)
    raise ValueError(f"Suite desconocida: {suite} (usa 'quick' o 'full')")
