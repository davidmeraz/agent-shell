"""Interfaz de línea de comandos para el benchmark de Agent Shell."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .metrics import (
    compare_reports,
    format_audit_report,
    format_comparison,
    format_run_report,
)
from .runner import PROJECT_ROOT, audit_history, run_benchmark, save_report
from .tasks import TASKS


def _cmd_list(_args: argparse.Namespace) -> int:
    print(f"{'ID':<22} {'Suite':<7} {'Turnos':>6}  Descripción")
    print("-" * 88)
    for task in TASKS:
        print(f"{task.task_id:<22} {task.suite:<7} {len(task.prompts):>6}  {task.description}")
    return 0


def _cmd_audit(args: argparse.Namespace) -> int:
    root = args.history_root or (PROJECT_ROOT / ".runtime" / "chats")
    report = audit_history(root)
    if args.save:
        saved = save_report({**report, "mode": "audit", "label": args.label or "audit"}, args.output)
        print(f"Snapshot guardado en: {saved}", file=sys.stderr)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(format_audit_report(report))
    return 0


def _cmd_run(args: argparse.Namespace) -> int:
    task_ids = [t.strip() for t in args.tasks.split(",") if t.strip()] if args.tasks else None
    progress = (lambda msg: print(msg, file=sys.stderr, flush=True)) if not args.quiet else None
    report = run_benchmark(
        live=args.live,
        suite=args.suite,
        task_ids=task_ids,
        model=args.model,
        effort=args.effort,
        label=args.label,
        session_root=args.session_root,
        check_quota=not args.no_quota,
        turn_timeout=args.turn_timeout,
        on_progress=progress,
    )
    saved = save_report(report, args.output)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print()
        print(format_run_report(report))
        print(f"\nReporte guardado en: {saved}")
    return 0 if report["summary"]["tasks_passed"] == report["summary"]["tasks_total"] else 2


def _cmd_compare(args: argparse.Namespace) -> int:
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    candidate = json.loads(args.candidate.read_text(encoding="utf-8"))
    diff = compare_reports(baseline, candidate)
    if args.json:
        print(json.dumps(diff, ensure_ascii=False, indent=2))
    else:
        print(format_comparison(diff, markdown=args.markdown))
    return 1 if diff["overall_verdict"].startswith("REGRESIÓN") else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="bench.sh",
        description="Benchmark y auditoría de tokens para Agent Shell",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_list = sub.add_parser("list", help="Lista las tareas reproducibles del benchmark")
    p_list.set_defaults(func=_cmd_list)

    p_audit = sub.add_parser("audit", help="Audita el historial real en .runtime/chats (0 cuota)")
    p_audit.add_argument("--history-root", type=Path, default=None)
    p_audit.add_argument("--save", action="store_true", help="Guarda el resumen en .runtime/benchmarks/")
    p_audit.add_argument("--label", default="")
    p_audit.add_argument("--output", type=Path, default=None)
    p_audit.add_argument("--json", action="store_true")
    p_audit.set_defaults(func=_cmd_audit)

    p_run = sub.add_parser("run", help="Ejecuta el benchmark contra HarnessServer real")
    mode = p_run.add_mutually_exclusive_group()
    mode.add_argument("--mock", action="store_true", help="Ejecución offline simulada (por defecto, 0 cuota)")
    mode.add_argument("--live", action="store_true", help="Ejecución real contra tu cuenta de ChatGPT")
    p_run.add_argument("--suite", choices=["quick", "full"], default="quick",
                       help="quick=2 tareas clave (t2+t5), full=5 tareas completas")
    p_run.add_argument("--tasks", default="", help="IDs separados por coma (sobrescribe --suite)")
    p_run.add_argument("--model", default="", help="Slug del modelo (vacío = predeterminado de la cuenta)")
    p_run.add_argument("--effort", default="", help="Esfuerzo de razonamiento (p. ej. low, medium, high)")
    p_run.add_argument("--label", default="", help="Etiqueta para identificar esta corrida (p. ej. baseline-v0.15)")
    p_run.add_argument("--session-root", type=Path, default=None)
    p_run.add_argument("--no-quota", action="store_true", help="No consultar delta de cuota con Codex")
    p_run.add_argument("--turn-timeout", type=float, default=900.0)
    p_run.add_argument("--output", type=Path, default=None, help="Ruta exacta para guardar el JSON")
    p_run.add_argument("--quiet", action="store_true")
    p_run.add_argument("--json", action="store_true")
    p_run.set_defaults(func=_cmd_run)

    p_cmp = sub.add_parser("compare", help="Compara dos reportes JSON (baseline vs candidato)")
    p_cmp.add_argument("baseline", type=Path)
    p_cmp.add_argument("candidate", type=Path)
    p_cmp.add_argument("--markdown", action="store_true", help="Salida en tabla Markdown")
    p_cmp.add_argument("--json", action="store_true")
    p_cmp.set_defaults(func=_cmd_compare)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (ValueError, RuntimeError, OSError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
