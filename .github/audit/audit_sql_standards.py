#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Auditoría de estándares SQL para SQL Server (T-SQL) con heurísticas ligeras
y configuración externa. Pensado para correr en CI.

Incluye:
- Stripper de comentarios /* ... */ y '-- ...'
- Reglas:
  * WITH (NOLOCK) detrás de FROM/JOIN                       (error)
  * Caracteres especiales no permitidos                     (error)
  * Temporales globales (##)                                (error)
  * Nombres temporales genéricos (#tmp/#temp)               (warning)
  * Uso de CURSOR                                           (error)
  * Funciones de usuario en WHERE                           (error)
  * Múltiples JOIN sin WHERE                                (warning)
  * SELECT *                                                (error)
  * SELECT TOP(...)                                         (warning)
  * UPDATE/DELETE sin WHERE                                 (error)
  * INSERT sin lista de columnas                            (error)
  * EXEC/sp_executesql con SQL dinámico no parametrizado    (error)
  * SELECT DISTINCT (silenciable con '-- distinct-ok')      (warning)

Mejoras de rendimiento:
- Patrones regex precompilados (global).
- Compilación única del patrón de caracteres especiales.
- Exclusión de directorios desde config.
- Salto de archivos grandes por umbral (MB) desde config.
"""

from __future__ import annotations

import os
import re
import sys
import logging
from pathlib import Path
from configparser import ConfigParser
from typing import Dict, List, Tuple

# ======================
# Configuración por defecto
# ======================

DEFAULT_CONFIG_PATH = ".github/audit/audit_config.ini"

DEFAULT_SEVERITIES: Dict[str, str] = {
    # Reglas existentes
    "nolock": "error",
    "special_chars": "error",
    "global_temp": "error",
    "temp_names": "warning",
    "cursors": "error",
    "user_functions": "error",
    "inner_join_where": "warning",
    "select_star": "error",
    "select_top": "warning",
    # Reglas nuevas
    "update_delete_no_where": "error",
    "insert_no_column_list": "error",
    "dynamic_sql_exec": "error",
    "select_distinct": "warning",
}

# ======================
# Utilidades
# ======================

def load_config(path: str = DEFAULT_CONFIG_PATH) -> ConfigParser:
    cfg = ConfigParser()
    if not Path(path).exists():
        raise FileNotFoundError(f"No se encontró el archivo de configuración: {path}")
    cfg.read(path, encoding="utf-8")
    return cfg

def setup_logging(cfg: ConfigParser) -> None:
    level = getattr(logging, (cfg.get("log", "level", fallback="INFO") or "INFO").upper(), logging.INFO)
    logging.basicConfig(level=level, format="%(levelname)s: %(message)s")
    logging.debug("Logger inicializado.")

def get_excluded_dirs(cfg: ConfigParser) -> set[str]:
    base = {".git", ".github", ".config", ".venv", "venv", ".idea", ".pytest_cache", "__pycache__"}
    extra = {d.strip() for d in cfg.get("paths", "exclude_dirs", fallback="").split(",") if d.strip()}
    return base | extra

def get_max_file_bytes(cfg: ConfigParser) -> int:
    mb = cfg.getint("limits", "max_file_mb", fallback=0)
    return mb * 1024 * 1024 if mb > 0 else 0

def iter_sql_files(root: Path, excluded: set[str]) -> List[Path]:
    files: List[Path] = []
    for base, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in excluded]
        for f in filenames:
            if f.lower().endswith(".sql"):
                files.append(Path(base) / f)
    return files

def rule_enabled(cfg: ConfigParser, name: str, default: bool = True) -> bool:
    return cfg.getboolean("rules", name, fallback=default)

def rule_severity(cfg: ConfigParser, name: str) -> str:
    return cfg.get("severities", name, fallback=DEFAULT_SEVERITIES.get(name, "warning")).lower()

def read_file_lines(p: Path) -> List[str]:
    try:
        return p.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception as e:
        logging.error(f"No se pudo leer {p}: {e}")
        return []

def compile_special_charclass(chars_text: str) -> re.Pattern:
    """
    Construye una clase de caracteres a partir de líneas con caracteres a bloquear.
    Si el archivo trae varias líneas, todos se agregan a la clase.
    """
    chars = []
    for line in chars_text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        chars.append(re.escape(s))
    if not chars:
        # fallback: caracteres fuera de ASCII básico
        return re.compile(r"[^\x09\x0A\x0D\x20-\x7E]")
    return re.compile("[" + "".join(chars) + "]")

def strip_inline_and_block_comments(lines: List[str]) -> List[str]:
    """
    Quita comentarios de línea '-- ...' y de bloque '/* ... */' preservando el número de líneas
    (inserta vacíos cuando corresponde) para mantener referencias de número de línea.
    """
    cleaned: List[str] = []
    in_block = False
    for ln in lines:
        s = ln
        if in_block:
            if "*/" in s:
                s = s.split("*/", 1)[1]
                in_block = False
            else:
                cleaned.append("")
                continue
        while "/*" in s:
            pre, rest = s.split("/*", 1)
            if "*/" in rest:
                rest = rest.split("*/", 1)[1]
                s = pre + " " + rest
            else:
                s = pre
                in_block = True
                break
        s = s.split("--", 1)[0]
        cleaned.append(s)
    return cleaned

# ======================
# Patrones precompilados (performance)
# ======================

RE_FROM = re.compile(r"\bFROM\b", re.IGNORECASE)
RE_JOIN = re.compile(r"\bJOIN\b", re.IGNORECASE)
RE_WITH_NOLOCK = re.compile(r"\bWITH\s*\(\s*NOLOCK\s*\)", re.IGNORECASE)
RE_FROM_OR_JOIN_TABLE = re.compile(r"\b(?:FROM|JOIN)\s+([#@\[\]\w\.]+)", re.IGNORECASE)

RE_GLOBAL_TEMP = re.compile(r"\b##[A-Za-z0-9_]+\b")
RE_TEMP_GENERIC = re.compile(r"\b#[Tt][Ee][Mm][Pp]\b|\b#tmp\b|\b#temp\b", re.IGNORECASE)

RE_CURSOR = re.compile(r"\bDECLARE\s+\w+\s+CURSOR\b|\bOPEN\s+\w+\b|\bFETCH\s+NEXT\b", re.IGNORECASE)

RE_USER_FUNC_IN_WHERE = re.compile(
    r"\bWHERE\b.*?(?:\b[dD][bB][oO]\s*\.\s*|[A-Za-z_]\w*\s*\.\s*)[A-Za-z_]\w*\s*\(",
    re.IGNORECASE
)

RE_SELECT = re.compile(r"^\s*SELECT\b", re.IGNORECASE)
RE_SELECT_STAR = re.compile(r"\bSELECT\b[^;]*\*", re.IGNORECASE)
RE_SELECT_TOP = re.compile(r"\bSELECT\b[^;]*\bTOP\s*\(", re.IGNORECASE)
RE_SELECT_DISTINCT = re.compile(r"\bSELECT\s+DISTINCT\b", re.IGNORECASE)

RE_STATEMENT_END = re.compile(r";\s*$")
RE_GO = re.compile(r"^\s*GO\s*$", re.IGNORECASE)

RE_UPDATE_OR_DELETE_START = re.compile(r"^\s*(UPDATE|DELETE)\b", re.IGNORECASE)
RE_INSERT_START = re.compile(r"^\s*INSERT\s+(?:INTO\s+)?([#@\[\]\w\.]+)(.*)$", re.IGNORECASE)

RE_EXEC = re.compile(r"\bEXEC(?:UTE)?\b", re.IGNORECASE)
RE_EXEC_CONCAT = re.compile(r"EXEC(?:UTE)?\s*\(?\s*(?:N)?'.*?'\s*\+\s*|EXEC(?:UTE)?\s*\(?\s*.*?\+\s*@\w+",
                            re.IGNORECASE)
RE_SP_EXECUTESQL = re.compile(r"\bsp_executesql\b", re.IGNORECASE)
RE_SP_PARAMS_DECL = re.compile(r"sp_executesql\s+N?'.*?'\s*,\s*N?'.*?@\w+\s+", re.IGNORECASE)
RE_SP_PARAMS_ASSIGN = re.compile(r"@\w+\s*=", re.IGNORECASE)

# ======================
# Reglas (checks)
# ======================

def check_nolock_present(lines: List[str]) -> List[str]:
    """
    Detecta WITH (NOLOCK) detrás de FROM/JOIN, permitiendo excepciones:
    - Tablas del sistema (sys.*)
    - Tablas temporales (#, ##)
    Nota: usa líneas sin comentarios para menos falsos positivos.
    """
    issues = []
    clines = strip_inline_and_block_comments(lines)
    for i, ln in enumerate(clines, 1):
        if not (RE_FROM.search(ln) or RE_JOIN.search(ln)):
            continue
        if RE_WITH_NOLOCK.search(ln):
            m = RE_FROM_OR_JOIN_TABLE.search(ln)
            if m:
                tname = m.group(1)
                if tname.startswith("sys.") or tname.startswith("#") or tname.startswith("##"):
                    continue
            issues.append(f"   Línea {i}: WITH (NOLOCK) detectado; evita lecturas sucias.")
    return issues

def check_special_chars(lines: List[str], special_char_pat: re.Pattern) -> List[str]:
    issues = []
    for i, ln in enumerate(lines, 1):
        if special_char_pat.search(ln):
            issues.append(f"   Línea {i}: Caracteres especiales no permitidos.")
    return issues

def check_global_temp_tables(lines: List[str]) -> List[str]:
    issues = []
    for i, ln in enumerate(lines, 1):
        if RE_GLOBAL_TEMP.search(ln):
            issues.append(f"   Línea {i}: Tabla temporal global (##) detectada.")
    return issues

def check_temp_names_generic(lines: List[str]) -> List[str]:
    issues = []
    for i, ln in enumerate(lines, 1):
        if RE_TEMP_GENERIC.search(ln):
            issues.append(f"   Línea {i}: Nombre temporal genérico (#tmp/#temp); usa nombres descriptivos.")
    return issues

def check_cursors(lines: List[str]) -> List[str]:
    issues = []
    for i, ln in enumerate(lines, 1):
        if RE_CURSOR.search(ln):
            issues.append(f"   Línea {i}: Uso de CURSOR detectado; evalúa set-based o WHILE.")
    return issues

def check_user_functions_in_where(lines: List[str]) -> List[str]:
    issues = []
    for i, ln in enumerate(lines, 1):
        if RE_USER_FUNC_IN_WHERE.search(ln):
            issues.append(f"   Línea {i}: Función de usuario en WHERE; podría impedir índices.")
    return issues

def check_inner_join_then_where(lines: List[str]) -> List[str]:
    issues = []
    join_count = 0
    in_block = False
    start_line = None
    for i, ln in enumerate(lines, 1):
        s = ln.strip()
        if RE_SELECT.search(s) and not in_block:
            in_block = True
            join_count = 0
            start_line = i
        if in_block:
            if RE_JOIN.search(s):
                join_count += 1
            if re.search(r"\bWHERE\b", s, re.IGNORECASE):
                in_block = False
                continue
            if RE_STATEMENT_END.search(s) or RE_GO.search(s):
                if join_count >= 2:
                    issues.append(f"   Línea {start_line}: Múltiples JOIN sin WHERE; valida selectividad.")
                in_block = False
    return issues

def check_select_star(lines: List[str]) -> List[str]:
    issues = []
    clines = strip_inline_and_block_comments(lines)
    for i, ln in enumerate(clines, 1):
        if RE_SELECT_STAR.search(ln):
            issues.append(f"   Línea {i}: SELECT * detectado; especifica columnas.")
    return issues

def check_select_top(lines: List[str]) -> List[str]:
    issues = []
    clines = strip_inline_and_block_comments(lines)
    for i, ln in enumerate(clines, 1):
        if RE_SELECT_TOP.search(ln):
            issues.append(f"   Línea {i}: SELECT TOP(...) detectado; valida paginación y orden.")
    return issues

def check_update_delete_without_where(lines: List[str]) -> List[str]:
    clines = strip_inline_and_block_comments(lines)
    issues: List[str] = []
    buffering = False
    start_line = None
    buf: List[str] = []
    def _finalize():
        nonlocal buf, start_line
        if not buf:
            return
        joined = " ".join(buf)
        if re.search(r"^\s*DELETE\b", joined, re.IGNORECASE) or re.search(r"^\s*UPDATE\b", joined, re.IGNORECASE):
            if not re.search(r"\bWHERE\b", joined, re.IGNORECASE):
                op = "DELETE" if re.search(r"^\s*DELETE\b", joined, re.IGNORECASE) else "UPDATE"
                issues.append(f"   Línea {start_line}: {op} sin WHERE")
        buf = []
        start_line = None
    for i, ln in enumerate(clines, 1):
        line = ln.strip()
        if not buffering and RE_UPDATE_OR_DELETE_START.search(line):
            buffering = True
            start_line = i
            buf = [line]
            if RE_STATEMENT_END.search(line) or RE_GO.search(line):
                buffering = False
                _finalize()
            continue
        if buffering:
            buf.append(line)
            if RE_STATEMENT_END.search(line) or RE_GO.search(line):
                buffering = False
                _finalize()
    if buffering:
        _finalize()
    return issues

def check_insert_without_column_list(lines: List[str]) -> List[str]:
    clines = strip_inline_and_block_comments(lines)
    issues: List[str] = []
    buffering = False
    start_line = None
    saw_open_paren = False
    pending = False
    for i, ln in enumerate(clines, 1):
        line = ln.strip()
        if not buffering:
            m = RE_INSERT_START.search(line)
            if m:
                buffering = True
                start_line = i
                rest = m.group(2) or ""
                saw_open_paren = "(" in rest
                pending = True
                if re.search(r"\b(VALUES|SELECT)\b", rest, re.IGNORECASE):
                    if not saw_open_paren:
                        issues.append(f"   Línea {start_line}: INSERT sin lista de columnas")
                    buffering = False
                    pending = False
            continue
        if buffering:
            if "(" in line and not saw_open_paren:
                saw_open_paren = True
            if re.search(r"\b(VALUES|SELECT)\b", line, re.IGNORECASE):
                if pending and not saw_open_paren:
                    issues.append(f"   Línea {start_line}: INSERT sin lista de columnas")
                buffering = False
                pending = False
                continue
            if RE_STATEMENT_END.search(line) or RE_GO.search(line):
                buffering = False
                pending = False
    return issues

def check_dynamic_sql_exec(lines: List[str]) -> List[str]:
    clines = strip_inline_and_block_comments(lines)
    issues: List[str] = []
    for i, ln in enumerate(clines, 1):
        s = ln
        if not RE_EXEC.search(s):
            continue
        if RE_EXEC_CONCAT.search(s):
            issues.append(f"   Línea {i}: EXEC con SQL dinámico concatenado; usa sp_executesql con parámetros.")
            continue
        if RE_SP_EXECUTESQL.search(s):
            has_params_decl = RE_SP_PARAMS_DECL.search(s)
            has_params_assign = RE_SP_PARAMS_ASSIGN.search(s)
            if not (has_params_decl and has_params_assign):
                issues.append(f"   Línea {i}: sp_executesql sin parámetros; parametriza los valores.")
    return issues

def check_select_distinct(lines: List[str]) -> List[str]:
    issues: List[str] = []
    for i, ln in enumerate(lines, 1):
        if RE_SELECT_DISTINCT.search(ln) and not re.search(r"distinct-ok", ln, re.IGNORECASE):
            issues.append(f"   Línea {i}: SELECT DISTINCT (valida necesidad o documenta con '-- distinct-ok').")
    return issues

# ======================
# Auditoría por archivo
# ======================

def audit_file(
    p: Path,
    cfg: ConfigParser,
    special_char_pat: re.Pattern
) -> Dict[str, List[str]]:
    lines = read_file_lines(p)
    results: Dict[str, List[str]] = {}
    if rule_enabled(cfg, "nolock", True):
        results["nolock"] = check_nolock_present(lines)
    if rule_enabled(cfg, "special_chars", True):
        results["special_chars"] = check_special_chars(lines, special_char_pat)
    if rule_enabled(cfg, "global_temp", True):
        results["global_temp"] = check_global_temp_tables(lines)
    if rule_enabled(cfg, "temp_names", True):
        results["temp_names"] = check_temp_names_generic(lines)
    if rule_enabled(cfg, "cursors", True):
        results["cursors"] = check_cursors(lines)
    if rule_enabled(cfg, "user_functions", True):
        results["user_functions"] = check_user_functions_in_where(lines)
    if rule_enabled(cfg, "inner_join_where", True):
        results["inner_join_where"] = check_inner_join_then_where(lines)
    if rule_enabled(cfg, "select_star", True):
        results["select_star"] = check_select_star(lines)
    if rule_enabled(cfg, "select_top", True):
        results["select_top"] = check_select_top(lines)
    # Nuevas
    if rule_enabled(cfg, "update_delete_no_where", True):
        results["upd_del"] = check_update_delete_without_where(lines)
    if rule_enabled(cfg, "insert_no_column_list", True):
        results["ins_cols"] = check_insert_without_column_list(lines)
    if rule_enabled(cfg, "dynamic_sql_exec", True):
        results["dyn_exec"] = check_dynamic_sql_exec(lines)
    if rule_enabled(cfg, "select_distinct", True):
        results["distinct"] = check_select_distinct(lines)
    return results

def print_results_for_file(p: Path, cfg: ConfigParser, res: Dict[str, List[str]]) -> Tuple[bool, bool]:
    print(f"\nArchivo: {p}")
    any_issue_as_error = False
    any_issue = False
    def show(rule_key: str, title: str, items: List[str]) -> None:
        nonlocal any_issue_as_error, any_issue
        if not items:
            return
        sev = rule_severity(cfg, rule_key)
        badge = {"error": "⛔", "warning": "⚠️", "off": "⚪"}.get(sev, "⚠️")
        print(f"  {badge} {title} ({sev})")
        for it in items:
            print(it)
        if sev == "error":
            any_issue_as_error = True
        any_issue = True
    show("nolock", "WITH (NOLOCK) detectado:", res.get("nolock", []))
    show("special_chars", "Caracteres especiales:", res.get("special_chars", []))
    show("global_temp", "Temporales globales (##):", res.get("global_temp", []))
    show("temp_names", "Nombres temporales genéricos:", res.get("temp_names", []))
    show("cursors", "Uso de CURSOR:", res.get("cursors", []))
    show("user_functions", "Funciones en WHERE:", res.get("user_functions", []))
    show("inner_join_where", "JOINs sin WHERE:", res.get("inner_join_where", []))
    show("select_star", "SELECT *:", res.get("select_star", []))
    show("select_top", "SELECT TOP:", res.get("select_top", []))
    # Nuevas
    show("update_delete_no_where", "UPDATE/DELETE sin WHERE:", res.get("upd_del", []))
    show("insert_no_column_list", "INSERT sin lista de columnas:", res.get("ins_cols", []))
    show("dynamic_sql_exec", "SQL dinámico no parametrizado (EXEC/sp_executesql):", res.get("dyn_exec", []))
    show("select_distinct", "SELECT DISTINCT detectado:", res.get("distinct", []))
    return any_issue, any_issue_as_error

# ======================
# main
# ======================

def main() -> int:
    cfg = load_config(DEFAULT_CONFIG_PATH)
    setup_logging(cfg)

    roots_value = cfg.get("paths", "sql_roots", fallback=".")
    roots = [Path(r.strip()) for r in roots_value.split(",") if r.strip()]

    # Compilar una vez el patrón de caracteres especiales
    special_chars_path = cfg.get("paths", "special_chars_file", fallback="")
    if special_chars_path and Path(special_chars_path).exists():
        special_chars_text = Path(special_chars_path).read_text(encoding="utf-8", errors="ignore")
        special_char_pat = compile_special_charclass(special_chars_text)
    else:
        special_char_pat = compile_special_charclass("")

    # Mejoras de rendimiento
    excluded = get_excluded_dirs(cfg)
    max_bytes = get_max_file_bytes(cfg)

    overall_any_issue = False
    overall_error = False

    for root in roots:
        if not root.exists():
            logging.warning(f"Ruta no encontrada: {root}")
            continue
        files = iter_sql_files(root, excluded)
        for f in files:
            try:
                if max_bytes and f.exists() and f.stat().st_size > max_bytes:
                    logging.info(f"Saltando archivo grande (> {max_bytes} bytes): {f}")
                    continue
            except OSError as e:
                logging.warning(f"No se pudo obtener tamaño de {f}: {e}")
            res = audit_file(f, cfg, special_char_pat)
            has_any, has_err = print_results_for_file(f, cfg, res)
            overall_any_issue = overall_any_issue or has_any
            overall_error = overall_error or has_err

    if not overall_any_issue:
        print("\n✅ Sin hallazgos. ¡Todo limpio!")
        return 0
    if overall_error:
        print("\n⛔ Se encontraron hallazgos con severidad 'error'.")
        return 1
    print("\n⚠️ Solo hallazgos con severidad 'warning'.")
    return 0

if __name__ == "__main__":
    sys.exit(main())