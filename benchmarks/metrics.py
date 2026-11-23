"""Agregación de métricas, comparación A/B y formateo de reportes del benchmark."""

from __future__ import annotations

import statistics
import subprocess
from pathlib import Path
from typing import Any


def git_metadata(project_root: Path) -> dict[str, Any]:
    def _git(*args: str) -> str:
        try:
            proc = subprocess.run(
                ["git", *args], cwd=project_root, capture_output=True, text=True, timeout=5,
            )
            return proc.stdout.strip() if proc.returncode == 0 else ""
        except (OSError, subprocess.SubprocessError):
            return ""

    return {
        "commit": _git("rev-parse", "--short", "HEAD") or "unknown",
        "branch": _git("rev-parse", "--abbrev-ref", "HEAD") or "unknown",
        "dirty": bool(_git("status", "--porcelain")),
    }


def _pct(part: int | float, whole: int | float) -> float | None:
    if not whole:
        return None
    return round((part / whole) * 100.0, 1)


def summarize_steps(steps: list[dict[str, Any]]) -> dict[str, Any]:
    """Resume los pasos HTTP individuales capturados por el proxy del benchmark."""
    in_tok = sum(s.get("input_tokens") or 0 for s in steps)
    cached_tok = sum(s.get("cached_tokens") or 0 for s in steps)
    uncached_in = max(0, in_tok - cached_tok)
    out_tok = sum(s.get("output_tokens") or 0 for s in steps)
    reason_tok = sum(s.get("reasoning_tokens") or 0 for s in steps)
    total_tok = sum(s.get("total_tokens") or 0 for s in steps)
    tool_calls = sum(s.get("tool_calls_returned") or 0 for s in steps)
    http_ms = round(sum(s.get("http_ms") or 0.0 for s in steps), 1)
    payload_bytes = sum(s.get("payload_bytes") or 0 for s in steps)
    max_ctx = max((s.get("input_tokens") or 0 for s in steps), default=0)

    # Pasos 2..N dentro de la misma tarea: aquí es donde el Prompt Cache DEBE acertar.
    followups = steps[1:]
    f_in = sum(s.get("input_tokens") or 0 for s in followups)
    f_cached = sum(s.get("cached_tokens") or 0 for s in followups)

    calls = len(steps)
    tools_offered: list[str] = []
    for step in steps:
        for name in step.get("tools_offered") or []:
            if name not in tools_offered:
                tools_offered.append(name)

    return {
        "model_calls": calls,
        "tool_calls": tool_calls,
        "tools_per_call": round(tool_calls / calls, 2) if calls else 0.0,
        "input_tokens": in_tok,
        "cached_tokens": cached_tok,
        "uncached_input_tokens": uncached_in,
        "output_tokens": out_tok,
        "reasoning_tokens": reason_tok,
        "total_tokens": total_tok,
        "cache_hit_rate": _pct(cached_tok, in_tok),
        "followup_cache_hit_rate": _pct(f_cached, f_in),
        "max_context_tokens": max_ctx,
        "http_ms": http_ms,
        "payload_bytes": payload_bytes,
        "has_prompt_cache_key": any(s.get("has_prompt_cache_key") for s in steps),
        "parallel_tool_calls": any(s.get("parallel_tool_calls") for s in steps),
        "tools_offered": tools_offered,
    }


def summarize_run(task_results: list[dict[str, Any]]) -> dict[str, Any]:
    """Agrega resultados de todas las tareas de una corrida del benchmark."""
    total_tasks = len(task_results)
    passed_tasks = sum(1 for r in task_results if r["verified"]["passed"])
    all_steps = [step for r in task_results for step in r.get("steps", [])]
    agg = summarize_steps(all_steps)

    # Recalcular followup_cache_hit_rate usando los pasos 2..N de CADA tarea (no cruzar tareas).
    f_in = sum(s.get("input_tokens") or 0 for r in task_results for s in r.get("steps", [])[1:])
    f_cached = sum(s.get("cached_tokens") or 0 for r in task_results for s in r.get("steps", [])[1:])
    agg["followup_cache_hit_rate"] = _pct(f_cached, f_in)

    wasted_uncached = sum(
        r["metrics"]["uncached_input_tokens"] + r["metrics"]["output_tokens"]
        for r in task_results
        if not r["verified"]["passed"]
    )
    duration_ms = round(sum(r.get("duration_ms", 0.0) for r in task_results), 1)

    return {
        **agg,
        "tasks_total": total_tasks,
        "tasks_passed": passed_tasks,
        "pass_rate": _pct(passed_tasks, total_tasks) or 0.0,
        "duration_ms": duration_ms,
        "wasted_billable_tokens": wasted_uncached,
        "effective_billable_tokens": agg["uncached_input_tokens"] + agg["output_tokens"],
    }


def _delta_pct(before: float | int | None, after: float | int | None) -> float | None:
    if before is None or after is None or before == 0:
        return None
    return round(((after - before) / before) * 100.0, 1)


def compare_reports(baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    """Compara dos corridas (baseline vs candidate) con regla estricta de calidad."""
    base_s = baseline["summary"]
    cand_s = candidate["summary"]

    base_map = {r["task_id"]: r for r in baseline.get("tasks", [])}
    cand_map = {r["task_id"]: r for r in candidate.get("tasks", [])}
    shared_ids = [tid for tid in base_map if tid in cand_map]

    per_task = []
    for tid in shared_ids:
        b = base_map[tid]
        c = cand_map[tid]
        bm, cm = b["metrics"], c["metrics"]
        b_pass = bool(b["verified"]["passed"])
        c_pass = bool(c["verified"]["passed"])
        b_bill = bm["uncached_input_tokens"] + bm["output_tokens"]
        c_bill = cm["uncached_input_tokens"] + cm["output_tokens"]
        bill_pct = _delta_pct(b_bill, c_bill)

        if b_pass and not c_pass:
            verdict = "REGRESIÓN"
        elif not b_pass and c_pass:
            verdict = "MEJORA"
        elif bill_pct is not None and bill_pct <= -5.0:
            verdict = "MEJORA"
        elif bill_pct is not None and bill_pct >= 5.0:
            verdict = "REGRESIÓN"
        else:
            verdict = "EMPATE"

        per_task.append({
            "task_id": tid,
            "base_passed": b_pass,
            "cand_passed": c_pass,
            "base_uncached_in": bm["uncached_input_tokens"],
            "cand_uncached_in": cm["uncached_input_tokens"],
            "uncached_delta_pct": _delta_pct(bm["uncached_input_tokens"], cm["uncached_input_tokens"]),
            "base_output": bm["output_tokens"],
            "cand_output": cm["output_tokens"],
            "output_delta_pct": _delta_pct(bm["output_tokens"], cm["output_tokens"]),
            "base_calls": bm["model_calls"],
            "cand_calls": cm["model_calls"],
            "base_cache_hit": bm["followup_cache_hit_rate"],
            "cand_cache_hit": cm["followup_cache_hit_rate"],
            "base_duration_ms": b.get("duration_ms", 0.0),
            "cand_duration_ms": c.get("duration_ms", 0.0),
            "verdict": verdict,
        })

    # Regla de oro: nunca celebrar ahorro de tokens si cayó la tasa de éxito.
    pass_delta = cand_s["tasks_passed"] - base_s["tasks_passed"]
    uncached_pct = _delta_pct(base_s["uncached_input_tokens"], cand_s["uncached_input_tokens"])
    out_pct = _delta_pct(base_s["output_tokens"], cand_s["output_tokens"])
    billable_pct = _delta_pct(base_s["effective_billable_tokens"], cand_s["effective_billable_tokens"])
    calls_pct = _delta_pct(base_s["model_calls"], cand_s["model_calls"])
    dur_pct = _delta_pct(base_s["duration_ms"], cand_s["duration_ms"])

    if pass_delta < 0:
        overall = "REGRESIÓN (cayó la calidad)"
    elif pass_delta > 0:
        overall = "MEJORA (subió la calidad)"
    elif billable_pct is not None and billable_pct <= -5.0:
        overall = "MEJORA (menos consumo manteniendo calidad)"
    elif billable_pct is not None and billable_pct >= 5.0:
        overall = "REGRESIÓN (más consumo sin ganar calidad)"
    else:
        overall = "EMPATE (sin cambio significativo)"

    warnings = []
    if baseline.get("model") != candidate.get("model"):
        warnings.append(
            f"Modelo distinto: {baseline.get('model')} vs {candidate.get('model')}"
        )
    if baseline.get("reasoning_effort", "") != candidate.get("reasoning_effort", ""):
        warnings.append(
            f"Esfuerzo distinto: {baseline.get('reasoning_effort') or 'auto'} vs "
            f"{candidate.get('reasoning_effort') or 'auto'}"
        )
    if set(base_map) != set(cand_map):
        warnings.append("Las dos corridas no contienen exactamente las mismas tareas.")

    return {
        "overall_verdict": overall,
        "warnings": warnings,
        "baseline": {
            "label": baseline.get("label", ""),
            "commit": baseline.get("git", {}).get("commit", ""),
            "model": baseline.get("model", ""),
            "effort": baseline.get("reasoning_effort", "") or "auto",
            "summary": base_s,
            "quota_delta": baseline.get("quota_delta"),
        },
        "candidate": {
            "label": candidate.get("label", ""),
            "commit": candidate.get("git", {}).get("commit", ""),
            "model": candidate.get("model", ""),
            "effort": candidate.get("reasoning_effort", "") or "auto",
            "summary": cand_s,
            "quota_delta": candidate.get("quota_delta"),
        },
        "deltas": {
            "tasks_passed": pass_delta,
            "uncached_input_pct": uncached_pct,
            "output_pct": out_pct,
            "billable_pct": billable_pct,
            "model_calls_pct": calls_pct,
            "duration_pct": dur_pct,
            "followup_cache_hit_pp": (
                round(cand_s["followup_cache_hit_rate"] - base_s["followup_cache_hit_rate"], 1)
                if cand_s["followup_cache_hit_rate"] is not None
                and base_s["followup_cache_hit_rate"] is not None
                else None
            ),
        },
        "tasks": per_task,
    }


def _fmt_int(value: int | None) -> str:
    return "—" if value is None else f"{value:,}"


def _fmt_pct(value: float | None, signed: bool = False) -> str:
    if value is None:
        return "—"
    prefix = "+" if signed and value > 0 else ""
    return f"{prefix}{value:.1f}%"


def _fmt_sec(ms: float | None) -> str:
    return "—" if ms is None else f"{ms / 1000.0:.1f}s"


def format_audit_report(audit: dict[str, Any]) -> str:
    lines = [
        "=== Auditoría de consumo histórico (.runtime/chats) ===",
        f"Chats analizados: {audit['chat_files']}  |  Turnos con uso: {audit['turns_with_usage']} / {audit['turns_total']}",
        "",
        f"{'Área':<8} {'Turnos':>6} {'Input':>11} {'Cacheado':>11} {'Hit%':>7} {'Uncached':>11} {'Output':>9} {'Mediana':>9} {'Fallos':>6}",
        "-" * 86,
    ]
    for area, row in audit["by_area"].items():
        lines.append(
            f"{area:<8} {row['turns']:>6} {_fmt_int(row['input_tokens']):>11} "
            f"{_fmt_int(row['cached_tokens']):>11} {_fmt_pct(row['cache_hit_rate']):>7} "
            f"{_fmt_int(row['uncached_input_tokens']):>11} {_fmt_int(row['output_tokens']):>9} "
            f"{_fmt_int(int(row['median_total_tokens'])):>9} {row['failed_turns']:>6}"
        )
    tot = audit["overall"]
    lines.extend([
        "-" * 86,
        f"{'TOTAL':<8} {tot['turns']:>6} {_fmt_int(tot['input_tokens']):>11} "
        f"{_fmt_int(tot['cached_tokens']):>11} {_fmt_pct(tot['cache_hit_rate']):>7} "
        f"{_fmt_int(tot['uncached_input_tokens']):>11} {_fmt_int(tot['output_tokens']):>9} "
        f"{_fmt_int(int(tot['median_total_tokens'])):>9} {tot['failed_turns']:>6}",
        "",
        f"Turnos multi-llamada (calls>=2): {audit['multicall_turns']}  "
        f"(con 0% caché: {audit['multicall_zero_cache']})",
        f"Relación media tools/llamada: {audit['tools_per_call']:.2f}  |  "
        f"Tokens quemados en fallos: {_fmt_int(audit['wasted_tokens_failed'])}",
    ])
    return "\n".join(lines)


def format_run_report(report: dict[str, Any]) -> str:
    s = report["summary"]
    git = report.get("git", {})
    lines = [
        f"=== Benchmark Agent Shell [{report['mode'].upper()}] · {report.get('label') or 'sin etiqueta'} ===",
        f"Commit: {git.get('commit', '?')}{'*' if git.get('dirty') else ''} ({git.get('branch', '?')})  |  "
        f"Modelo: {report.get('model') or '—'}  |  Esfuerzo: {report.get('reasoning_effort') or 'auto'}",
        f"Features detectadas en cable: prompt_cache_key={'SÍ' if s['has_prompt_cache_key'] else 'NO'}  |  "
        f"parallel_tool_calls={'SÍ' if s['parallel_tool_calls'] else 'NO'}  |  "
        f"tools={','.join(s['tools_offered']) or '—'}",
        "",
        f"{'Tarea':<22} {'OK':<4} {'Calls':>5} {'Tools':>5} {'Uncached':>10} {'Cached':>10} {'Hit2+':>7} {'Output':>8} {'MaxCtx':>8} {'Tiempo':>7}",
        "-" * 96,
    ]
    for task in report["tasks"]:
        m = task["metrics"]
        ok = "PASS" if task["verified"]["passed"] else "FAIL"
        lines.append(
            f"{task['task_id']:<22} {ok:<4} {m['model_calls']:>5} {m['tool_calls']:>5} "
            f"{_fmt_int(m['uncached_input_tokens']):>10} {_fmt_int(m['cached_tokens']):>10} "
            f"{_fmt_pct(m['followup_cache_hit_rate']):>7} {_fmt_int(m['output_tokens']):>8} "
            f"{_fmt_int(m['max_context_tokens']):>8} {_fmt_sec(task['duration_ms']):>7}"
        )
    lines.extend([
        "-" * 96,
        f"Aprobadas: {s['tasks_passed']}/{s['tasks_total']} ({_fmt_pct(s['pass_rate'])})  |  "
        f"Uncached: {_fmt_int(s['uncached_input_tokens'])}  |  "
        f"Output: {_fmt_int(s['output_tokens'])} (razonam: {_fmt_int(s['reasoning_tokens'])})  |  "
        f"Hit pasos 2+: {_fmt_pct(s['followup_cache_hit_rate'])}  |  "
        f"Tools/call: {s['tools_per_call']:.2f}  |  Tiempo: {_fmt_sec(s['duration_ms'])}",
    ])
    quota = report.get("quota_delta")
    if quota and quota.get("available"):
        parts = []
        if quota.get("primary_delta_pct") is not None:
            parts.append(f"5h: {_fmt_pct(quota['primary_delta_pct'], signed=True)}")
        if quota.get("secondary_delta_pct") is not None:
            parts.append(f"semanal: {_fmt_pct(quota['secondary_delta_pct'], signed=True)}")
        if quota.get("lifetime_tokens_delta") is not None:
            parts.append(f"codex_delta: {_fmt_int(quota['lifetime_tokens_delta'])}")
        if parts:
            lines.append("Delta real de cuota Codex → " + "  |  ".join(parts))
    return "\n".join(lines)


def format_comparison(diff: dict[str, Any], markdown: bool = False) -> str:
    b = diff["baseline"]
    c = diff["candidate"]
    bs, cs = b["summary"], c["summary"]
    d = diff["deltas"]

    base_pass_str = f"{bs['tasks_passed']}/{bs['tasks_total']}"
    cand_pass_str = f"{cs['tasks_passed']}/{cs['tasks_total']}"
    pass_delta_str = f"{d['tasks_passed']:+d}"
    hit_pp_str = "—" if d["followup_cache_hit_pp"] is None else f"{d['followup_cache_hit_pp']:+.1f} pp"

    lines: list[str] = []
    if markdown:
        lines.append(f"## Comparación: `{b['label'] or b['commit']}` → `{c['label'] or c['commit']}`")
        lines.append(f"**Veredicto:** **{diff['overall_verdict']}**")
        for warning in diff["warnings"]:
            lines.append(f"> ⚠️ {warning}")
        lines.extend([
            "",
            "| Métrica | Baseline | Candidato | Delta |",
            "| :--- | ---: | ---: | ---: |",
            f"| Tareas aprobadas | {base_pass_str} | {cand_pass_str} | {pass_delta_str} |",
            f"| Uncached input | {_fmt_int(bs['uncached_input_tokens'])} | {_fmt_int(cs['uncached_input_tokens'])} | {_fmt_pct(d['uncached_input_pct'], True)} |",
            f"| Output tokens | {_fmt_int(bs['output_tokens'])} | {_fmt_int(cs['output_tokens'])} | {_fmt_pct(d['output_pct'], True)} |",
            f"| Facturables (uncached+out) | {_fmt_int(bs['effective_billable_tokens'])} | {_fmt_int(cs['effective_billable_tokens'])} | {_fmt_pct(d['billable_pct'], True)} |",
            f"| Cache Hit pasos 2+ | {_fmt_pct(bs['followup_cache_hit_rate'])} | {_fmt_pct(cs['followup_cache_hit_rate'])} | {hit_pp_str} |",
            f"| Llamadas al modelo | {bs['model_calls']} | {cs['model_calls']} | {_fmt_pct(d['model_calls_pct'], True)} |",
            f"| Duración total | {_fmt_sec(bs['duration_ms'])} | {_fmt_sec(cs['duration_ms'])} | {_fmt_pct(d['duration_pct'], True)} |",
            "",
            "| Tarea | Base | Cand | Uncached Δ | Output Δ | Calls | Hit2+ | Veredicto |",
            "| :--- | :---: | :---: | ---: | ---: | :---: | :---: | :--- |",
        ])
        for row in diff["tasks"]:
            lines.append(
                f"| `{row['task_id']}` | {'PASS' if row['base_passed'] else 'FAIL'} | "
                f"{'PASS' if row['cand_passed'] else 'FAIL'} | "
                f"{_fmt_pct(row['uncached_delta_pct'], True)} | {_fmt_pct(row['output_delta_pct'], True)} | "
                f"{row['base_calls']}→{row['cand_calls']} | "
                f"{_fmt_pct(row['base_cache_hit'])}→{_fmt_pct(row['cand_cache_hit'])} | {row['verdict']} |"
            )
        return "\n".join(lines)

    lines.append(
        f"=== Comparación A/B: {b['label'] or b['commit']} ({b['commit']})  →  "
        f"{c['label'] or c['commit']} ({c['commit']}) ==="
    )
    lines.append(f"VEREDICTO: {diff['overall_verdict']}")
    for warning in diff["warnings"]:
        lines.append(f"AVISO: {warning}")
    lines.extend([
        "",
        f"{'Métrica':<28} {'Baseline':>14} {'Candidato':>14} {'Delta':>12}",
        "-" * 72,
        f"{'Tareas aprobadas':<28} {base_pass_str:>14} {cand_pass_str:>14} {pass_delta_str:>12}",
        f"{'Input NO cacheado':<28} {_fmt_int(bs['uncached_input_tokens']):>14} "
        f"{_fmt_int(cs['uncached_input_tokens']):>14} {_fmt_pct(d['uncached_input_pct'], True):>12}",
        f"{'Output tokens':<28} {_fmt_int(bs['output_tokens']):>14} "
        f"{_fmt_int(cs['output_tokens']):>14} {_fmt_pct(d['output_pct'], True):>12}",
        f"{'Facturable (uncached+out)':<28} {_fmt_int(bs['effective_billable_tokens']):>14} "
        f"{_fmt_int(cs['effective_billable_tokens']):>14} {_fmt_pct(d['billable_pct'], True):>12}",
        f"{'Cache Hit pasos 2+':<28} {_fmt_pct(bs['followup_cache_hit_rate']):>14} "
        f"{_fmt_pct(cs['followup_cache_hit_rate']):>14} {hit_pp_str:>12}",
        f"{'Llamadas al modelo':<28} {bs['model_calls']:>14} {cs['model_calls']:>14} "
        f"{_fmt_pct(d['model_calls_pct'], True):>12}",
        f"{'Duración total':<28} {_fmt_sec(bs['duration_ms']):>14} {_fmt_sec(cs['duration_ms']):>14} "
        f"{_fmt_pct(d['duration_pct'], True):>12}",
        "",
        f"{'Tarea':<22} {'OK':<9} {'Uncached Δ':>11} {'Out Δ':>9} {'Calls':>8} {'Hit2+':>15} {'Veredicto':<10}",
        "-" * 90,
    ])
    for row in diff["tasks"]:
        ok = f"{'P' if row['base_passed'] else 'F'}→{'P' if row['cand_passed'] else 'F'}"
        calls = f"{row['base_calls']}→{row['cand_calls']}"
        hit = f"{_fmt_pct(row['base_cache_hit'])}→{_fmt_pct(row['cand_cache_hit'])}"
        lines.append(
            f"{row['task_id']:<22} {ok:<9} {_fmt_pct(row['uncached_delta_pct'], True):>11} "
            f"{_fmt_pct(row['output_delta_pct'], True):>9} {calls:>8} {hit:>15} {row['verdict']:<10}"
        )
    return "\n".join(lines)


def compute_area_stats(turns: list[dict[str, Any]]) -> dict[str, Any]:
    """Estadísticas agregadas para un subconjunto de turnos de historial."""
    if not turns:
        return {
            "turns": 0, "input_tokens": 0, "cached_tokens": 0, "uncached_input_tokens": 0,
            "output_tokens": 0, "reasoning_tokens": 0, "total_tokens": 0,
            "cache_hit_rate": None, "median_total_tokens": 0, "failed_turns": 0,
        }
    in_tok = sum(t["input_tokens"] for t in turns)
    cached = sum(t["cached_tokens"] for t in turns)
    out_tok = sum(t["output_tokens"] for t in turns)
    reason = sum(t["reasoning_tokens"] for t in turns)
    total = sum(t["total_tokens"] for t in turns)
    return {
        "turns": len(turns),
        "input_tokens": in_tok,
        "cached_tokens": cached,
        "uncached_input_tokens": max(0, in_tok - cached),
        "output_tokens": out_tok,
        "reasoning_tokens": reason,
        "total_tokens": total,
        "cache_hit_rate": _pct(cached, in_tok),
        "median_total_tokens": statistics.median(t["total_tokens"] for t in turns),
        "failed_turns": sum(1 for t in turns if t["status"] == "failed"),
    }
