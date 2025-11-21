import os
import re
import sys
from pathlib import Path
import configparser

# -----------------------------
# Config: fija la ubicación del INI en .github/audit/
# -----------------------------
CFG_FIXED_PATH = Path(".github/audit/audit_config.ini")

def load_config_fixed(repo_root: Path) -> configparser.ConfigParser:
    cfg = configparser.ConfigParser()
    cfg_path = (repo_root / CFG_FIXED_PATH).resolve()
    if not cfg_path.exists():
        print(f"⚠️  No se encontró {cfg_path}. Usando defaults.")
    else:
        cfg.read(cfg_path, encoding="utf-8")
    return cfg

def parse_roots_from_config(cfg: configparser.ConfigParser, repo_root: Path) -> list[Path]:
    raw = cfg.get("paths", "sql_roots", fallback=".").strip()
    tokens = [t.strip() for t in raw.replace(";", ",").split(",") if t.strip()]
    roots = [(repo_root / t if not Path(t).is_absolute() else Path(t)) for t in (tokens or ["."])]
    out = []
    for r in roots:
        r = r.resolve()
        if r not in out:
            out.append(r)
    return out or [repo_root]

# -----------------------------
# Severidades por regla
# -----------------------------
DEFAULT_SEVERITIES = {
    "nolock": "error",
    "special_chars": "warning",
    "global_temp": "error",
    "temp_names": "warning",
    "cursors": "error",
    "user_functions": "error",
    "inner_join_where": "warning",
    "select_star": "error",
    "select_top": "error",
    "top_without_order_by": "error",
    "delete_update_without_where": "error",
    "merge_usage": "warning",
    "select_distinct_no_justification": "warning",
    "exec_dynamic_sql_unparameterized": "error",
    "select_into_heavy": "warning",
    "scalar_udf_in_select_where": "warning",
    "deprecated_types": "error",
    "hint_usage_general": "warning",
}

def sev(cfg, rule):
    s = cfg.get("severities", rule, fallback=DEFAULT_SEVERITIES.get(rule, "error")).lower()
    return "off" if s not in {"error", "warning", "off"} else s

def badge(severity):
    return "❌" if severity == "error" else "⚠️"

# -----------------------------
# Patrones comunes
# -----------------------------
nolock_pattern = re.compile(r"(WITH\s*)?\(\s*NOLOCK\s*(,\s*READUNCOMMITTED\s*)?\)", re.IGNORECASE)
nolock_paren_only_pattern = re.compile(r"\(\s*NOLOCK\s*(,\s*READUNCOMMITTED\s*)?\)", re.IGNORECASE)
ignore_temp_tables_pattern = re.compile(r"\bFROM\s+[#@]{1,2}[\w\d_]+", re.IGNORECASE)
global_temp_pattern = re.compile(r"##\w+", re.IGNORECASE)
bad_temp_names_pattern = re.compile(r"(#temp|@temp)\b", re.IGNORECASE)
cursor_pattern = re.compile(r"\bCURSOR\b", re.IGNORECASE)
user_function_in_where_pattern = re.compile(r"WHERE\s+.*?\b(?:dbo|db|schema|owner)\.\w+\s*\(.*?\)", re.IGNORECASE)

# UDF (genérico) en SELECT/WHERE (para regla 10)
udf_call_pattern = re.compile(r"\b(?:\w+\.){0,2}\w+\s*\(", re.IGNORECASE)

# Tipos deprecados (para regla 13)
deprecated_types_pattern = re.compile(r"\b(TEXT|NTEXT|IMAGE)\b", re.IGNORECASE)

# Hints generales comunes (para regla 14)
hints_pattern = re.compile(
    r"\bWITH\s*\(\s*INDEX\s*\(|\bFORCESEEK\b|\bFAST\s+\d+\b|\b(LOOP|HASH|MERGE)\s+JOIN\b|\bOPTION\s*\((?:[^)]*)\)",
    re.IGNORECASE
)

# sys.* y sysobjects (excepción en NOLOCK)
def is_sys_table(token: str) -> bool:
    t = token.strip().strip("[]")
    low = t.lower()
    if low == "sysobjects":
        return True
    parts = [p.strip("[]").lower() for p in t.split(".")]
    if parts and parts[0] == "sys":
        return True
    return False

# -----------------------------
# Carga de caracteres especiales
# -----------------------------
def compile_special_chars_pattern(cfg, repo_root: Path) -> re.Pattern:
    rel = cfg.get("paths", "special_chars_file", fallback=".github/audit/special_chars.txt").strip()
    path = (repo_root / rel) if not Path(rel).is_absolute() else Path(rel)
    chars = []
    if path.exists():
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                s = raw.strip()
                if not s or s.startswith("#"):
                    continue
                chars.append(s)
    if not chars:
        chars = list("áéíóúÁÉÍÓÚñÑ&%$¡¿")
    if all(len(c) == 1 for c in chars):
        escaped = "".join(re.escape(c) for c in chars)
        return re.compile(f"[{escaped}]")
    chars.sort(key=len, reverse=True)
    alt = "|".join(re.escape(c) for c in chars)
    return re.compile(alt, re.IGNORECASE)

# -----------------------------
# Reglas
# -----------------------------
def rule_enabled(cfg, key, default=True):
    return cfg.getboolean("rules", key, fallback=default)

def check_nolock(lines):
    issues = []
    # Excepciones contextuales:
    # - SELECT dentro de cursores (DECLARE ... CURSOR FOR ...)
    # - Bloques DML: INSERT / UPDATE / DELETE
    ignore_cursor_block = False
    ignore_dml_block = False

    for i, ln in enumerate(lines, 1):
        line = ln.rstrip("\n")

        # Detectar inicio de cursor
        if re.search(r"\bDECLARE\s+\w+\s+CURSOR\s+FOR\b", line, re.IGNORECASE):
            ignore_cursor_block = True

        # Detectar inicio de bloque DML (INSERT/UPDATE/DELETE)
        if re.search(r"\b(INSERT|UPDATE|DELETE)\b", line, re.IGNORECASE):
            ignore_dml_block = True

        # Si estamos dentro de un bloque cursor, no auditamos NOLOCK
        if ignore_cursor_block:
            if re.search(r"^\s*GO\s*$", line, re.IGNORECASE) or line.strip() == "":
                ignore_cursor_block = False
            continue

        # Si estamos dentro de un bloque DML, tampoco auditamos NOLOCK
        if ignore_dml_block:
            # Fin de bloque DML: ; o GO o línea en blanco
            if ";" in line or re.search(r"^\s*GO\s*$", line, re.IGNORECASE) or line.strip() == "":
                ignore_dml_block = False
            continue

        l = line.strip()

        # Comentarios o FROM sobre temporales/variables se omiten
        if l.startswith("--") or ignore_temp_tables_pattern.search(line):
            continue

        # Si ya tiene NOLOCK/READUNCOMMITTED, no reportamos
        if nolock_pattern.search(line) or nolock_paren_only_pattern.search(line):
            continue

        # Detectar FROM/JOIN tabla física
        m = re.search(r"\b(FROM|JOIN)\s+([\w.\[\]]+)", line, re.IGNORECASE)
        if m:
            table = m.group(2)
            # Excluir sys.*, sysobjects
            if is_sys_table(table):
                continue
            # Excluir temporales (#) y variables (@)
            if re.match(r"[#@]", table):
                continue
            issues.append(
                f"   Línea {i}: Falta hint WITH (NOLOCK) en {m.group(1).upper()} tabla '{table}'"
            )

    return issues

def check_special_chars(lines, special_chars_re):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines, 1) if special_chars_re.search(ln)]

def check_global_temp(lines):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines, 1)
            if not ln.strip().startswith('--') and global_temp_pattern.search(ln)]

def check_temp_names(lines):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines, 1)
            if not ln.strip().startswith('--') and bad_temp_names_pattern.search(ln)]

def check_cursors(lines):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines, 1)
            if not ln.strip().startswith('--') and cursor_pattern.search(ln)]

def check_user_funcs(lines):
    issues = []
    for i, ln in enumerate(lines, 1):
        if ln.strip().startswith("--"):
            continue
        if user_function_in_where_pattern.search(ln):
            issues.append(f"   Línea {i}: {ln.strip()}")
    return issues

def check_inner_join_warnings(lines):
    issues = []
    join_count = 0; first_join = None; has_variant = False; in_block = False
    for i, ln in enumerate(lines, 1):
        line = ln.strip()
        if not line or line.startswith("--"):
            continue
        if re.search(r"\bSELECT\b", line, re.IGNORECASE):
            join_count = 0; first_join = None; has_variant = False; in_block = True
        if not in_block:
            continue
        if re.search(r"\bINNER\s+JOIN\b", line, re.IGNORECASE):
            join_count += 1
            if first_join is None:
                first_join = i
        if re.search(r"\b(LEFT|RIGHT|FULL|OUTER)\s+JOIN\b", line, re.IGNORECASE):
            has_variant = True
        if re.search(r"\bWHERE\b", line, re.IGNORECASE):
            if join_count > 1 and not has_variant and first_join is not None:
                issues.append(f"   Línea {first_join}: Múltiples INNER JOIN + WHERE sin variantes")
            in_block = False; join_count = 0; has_variant = False; first_join = None
        if re.search(r";\s*$", line):
            in_block = False; join_count = 0; has_variant = False; first_join = None
    return issues

def check_select_star(lines):
    issues = []
    buffering = False; buf = []; start_line = None
    for i, ln in enumerate(lines, 1):
        line = ln.split("--", 1)[0]
        if not buffering and re.search(r"\bSELECT\b", line, re.IGNORECASE):
            buffering = True; start_line = i; buf = [line]
            if re.search(r"\bFROM\b", line, re.IGNORECASE):
                buffering = False
                joined = " ".join(buf)
                m = re.search(r"\bSELECT\b(?P<clause>.*?)\bFROM\b", joined, re.IGNORECASE | re.DOTALL)
                if m and re.fullmatch(r"\s*\*\s*", m.group("clause"), re.DOTALL):
                    issues.append(f"   Línea {start_line}: Uso de SELECT *")
                buf = []
            continue
        if buffering:
            buf.append(line)
            if re.search(r"\bFROM\b", line, re.IGNORECASE):
                buffering = False
                joined = " ".join(buf)
                m = re.search(r"\bSELECT\b(?P<clause>.*?)\bFROM\b", joined, re.IGNORECASE | re.DOTALL)
                if m and re.fullmatch(r"\s*\*\s*", m.group("clause"), re.DOTALL):
                    issues.append(f"   Línea {start_line}: Uso de SELECT *")
                buf = []
    return issues

def check_select_top(lines):
    issues = []
    buffering = False; buf = []; start_line = None
    for i, ln in enumerate(lines, 1):
        line = ln.split("--", 1)[0]
        if not buffering and re.search(r"\bSELECT\b", line, re.IGNORECASE):
            buffering = True; start_line = i; buf = [line]
            if re.search(r"\bFROM\b", line, re.IGNORECASE):
                buffering = False
                joined = " ".join(buf)
                m = re.search(r"\bSELECT\b(?P<clause>.*?)\bFROM\b", joined, re.IGNORECASE | re.DOTALL)
                if m and re.search(r"\bTOP\b", m.group("clause"), re.IGNORECASE):
                    issues.append(f"   Línea {start_line}: Uso de SELECT TOP")
                buf = []
            continue
        if buffering:
            buf.append(line)
            if re.search(r"\bFROM\b", line, re.IGNORECASE):
                buffering = False
                joined = " ".join(buf)
                m = re.search(r"\bSELECT\b(?P<clause>.*?)\bFROM\b", joined, re.IGNORECASE | re.DOTALL)
                if m and re.search(r"\bTOP\b", m.group("clause"), re.IGNORECASE):
                    issues.append(f"   Línea {start_line}: Uso de SELECT TOP")
                buf = []
    return issues

# -----------------------------
# Reglas nuevas
# -----------------------------
def check_top_without_order_by(lines):
    issues = []
    buffering = False; buf=[]; start_line=None
    for i, ln in enumerate(lines, 1):
        line = ln.split("--",1)[0]
        if not buffering and re.search(r"\bSELECT\b", line, re.IGNORECASE):
            buffering=True; buf=[line]; start_line=i
            continue
        if buffering:
            buf.append(line)
            if ";" in line or re.search(r"^\s*GO\s*$", line, re.IGNORECASE) or re.search(r"\bSELECT\b", line, re.IGNORECASE):
                stmt = " ".join(buf)
                if re.search(r"\bSELECT\s+TOP\b", stmt, re.IGNORECASE) and not re.search(r"\bORDER\s+BY\b", stmt, re.IGNORECASE):
                    issues.append(f"   Línea {start_line}: SELECT TOP sin ORDER BY determinista")
                buffering=False; buf=[]; start_line=None
    return issues

def check_delete_update_without_where(lines):
    issues = []
    buffering=False; buf=[]; start_line=None; kind=None
    for i, ln in enumerate(lines, 1):
        line = ln.split("--",1)[0]
        if not buffering:
            m = re.search(r"\b(DELETE|UPDATE)\b", line, re.IGNORECASE)
            if m:
                kind = m.group(1).upper(); buffering=True; buf=[line]; start_line=i
                continue
        else:
            buf.append(line)
            if ";" in line or re.search(r"^\s*GO\s*$", line, re.IGNORECASE):
                stmt = " ".join(buf)
                if not re.search(r"\bWHERE\b", stmt, re.IGNORECASE):
                    issues.append(f"   Línea {start_line}: {kind} sin cláusula WHERE")
                buffering=False; buf=[]; start_line=None; kind=None
    return issues

def check_merge_usage(lines):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines,1)
            if not ln.strip().startswith('--') and re.search(r"\bMERGE\b", ln, re.IGNORECASE)]

def check_select_distinct_no_justification(lines):
    issues=[]
    for i, ln in enumerate(lines,1):
        if re.search(r"\bSELECT\s+DISTINCT\b", ln, re.IGNORECASE):
            prev = lines[i-2:i-1] + lines[i-1:i]
            snippet = " ".join(prev + [ln])
            if not re.search(r"--\s*justification\s*:", snippet, re.IGNORECASE):
                issues.append(f"   Línea {i}: SELECT DISTINCT sin justificación (-- justification:)")
    return issues

def check_exec_dynamic_sql_unparameterized(lines):
    issues=[]
    joined = "\n".join(lines)
    pattern = re.compile(r"\bEXEC(?:UTE)?\b\s*(?:sp_executesql)?\s*\((?:[^)]*\+[^)]*)\)|\bsp_executesql\b\s+@?\w+\s*=.*\+.*", re.IGNORECASE|re.DOTALL)
    for m in pattern.finditer(joined):
        pos = joined[:m.start()].count("\n")+1
        issues.append(f"   Línea {pos}: SQL dinámico con concatenación no parametrizada")
    return issues

def check_select_into_heavy(lines):
    issues=[]
    for i, ln in enumerate(lines,1):
        line = ln.split("--",1)[0]
        if re.search(r"\bSELECT\b.*\bINTO\b\s+#\w+", line, re.IGNORECASE):
            issues.append(f"   Línea {i}: SELECT INTO #temp; recomienda CREATE TABLE + INSERT para control de tipos/índices")
    return issues

def check_scalar_udf_in_select_where(lines):
    """
    Detecta llamadas a UDF escalares en SELECT/WHERE: p.ej. dbo.fn(...), schema.fn(...).
    (Heurística: cualquier identificador 1-3 partes seguido de '(')
    """
    issues = []
    for i, ln in enumerate(lines, 1):
        if ln.strip().startswith("--"):
            continue
        l = ln.split("--",1)[0]
        if re.search(r"\bSELECT\b", l, re.IGNORECASE) or re.search(r"\bWHERE\b", l, re.IGNORECASE):
            if udf_call_pattern.search(l):
                issues.append(f"   Línea {i}: Posible UDF escalar en SELECT/WHERE -> {l.strip()}")
    return issues

def check_deprecated_types(lines):
    """
    Detecta tipos TEXT/NTEXT/IMAGE en cualquier definición/uso.
    """
    issues = []
    for i, ln in enumerate(lines, 1):
        if ln.strip().startswith("--"):
            continue
        if deprecated_types_pattern.search(ln):
            issues.append(f"   Línea {i}: Uso de tipo deprecado (TEXT/NTEXT/IMAGE)")
    return issues

def check_hint_usage_general(lines):
    """
    Detecta hints de consulta comunes:
      - WITH (INDEX(...)), FORCESEEK, FAST n
      - LOOP/HASH/MERGE JOIN
      - OPTION(RECOMPILE|OPTIMIZE FOR|USE HINT|QUERYTRACEON|...)
    """
    issues = []
    for i, ln in enumerate(lines, 1):
        if ln.strip().startswith("--"):
            continue
        if hints_pattern.search(ln):
            issues.append(f"   Línea {i}: Uso de hint de consulta -> {ln.strip()}")
    return issues

# -----------------------------
# Auditoría de archivo
# -----------------------------
def audit_file(fp: Path, cfg: configparser.ConfigParser, special_chars_re: re.Pattern):
    with open(fp, encoding="utf-8") as f:
        lines = f.read().splitlines(True)

    res = {
        "archivo": str(fp),
        "nolock": [], "special": [], "global": [], "temp": [],
        "curs": [], "funcs": [], "warn": [],
        "select_star": [], "select_top": [],
        "top_without_order_by": [], "delete_update_without_where": [], "merge_usage": [],
        "select_distinct_no_justification": [], "exec_dynamic_sql_unparameterized": [], "select_into_heavy": [],
        "scalar_udf_in_select_where": [], "deprecated_types": [], "hint_usage_general": []
    }

    if rule_enabled(cfg, "nolock", True):
        res["nolock"] = check_nolock(lines)
    if rule_enabled(cfg, "special_chars", True):
        res["special"] = check_special_chars(lines, special_chars_re)
    if rule_enabled(cfg, "global_temp", True):
        res["global"] = check_global_temp(lines)
    if rule_enabled(cfg, "temp_names", True):
        res["temp"] = check_temp_names(lines)
    if rule_enabled(cfg, "cursors", True):
        res["curs"] = check_cursors(lines)
    if rule_enabled(cfg, "user_functions", True):
        res["funcs"] = check_user_funcs(lines)
    if rule_enabled(cfg, "inner_join_where", True):
        res["warn"] = check_inner_join_warnings(lines)
    if rule_enabled(cfg, "select_star", True):
        res["select_star"] = check_select_star(lines)
    if rule_enabled(cfg, "select_top", True):
        res["select_top"] = check_select_top(lines)

    if rule_enabled(cfg, "top_without_order_by", True):
        res["top_without_order_by"] = check_top_without_order_by(lines)
    if rule_enabled(cfg, "delete_update_without_where", True):
        res["delete_update_without_where"] = check_delete_update_without_where(lines)
    if rule_enabled(cfg, "merge_usage", True):
        res["merge_usage"] = check_merge_usage(lines)
    if rule_enabled(cfg, "select_distinct_no_justification", True):
        res["select_distinct_no_justification"] = check_select_distinct_no_justification(lines)
    if rule_enabled(cfg, "exec_dynamic_sql_unparameterized", True):
        res["exec_dynamic_sql_unparameterized"] = check_exec_dynamic_sql_unparameterized(lines)
    if rule_enabled(cfg, "select_into_heavy", True):
        res["select_into_heavy"] = check_select_into_heavy(lines)

    if rule_enabled(cfg, "scalar_udf_in_select_where", True):
        res["scalar_udf_in_select_where"] = check_scalar_udf_in_select_where(lines)
    if rule_enabled(cfg, "deprecated_types", True):
        res["deprecated_types"] = check_deprecated_types(lines)
    if rule_enabled(cfg, "hint_usage_general", True):
        res["hint_usage_general"] = check_hint_usage_general(lines)

    return res

# -----------------------------
# Helpers de impresión
# -----------------------------
def show(rule_key: str, title: str, items: list, cfg: configparser.ConfigParser):
    s = sev(cfg, rule_key)
    if s == "off":
        return False
    if items:
        print(f"\n{badge(s)} [{rule_key}] {title} ({len(items)}):")
        for it in items:
            print(it)
        return s == "error"
    return False

# -----------------------------
# Main
# -----------------------------
def main():
    print("==== Auditoría iniciada ====\n")
    repo_root = Path.cwd().resolve()
    cfg = load_config_fixed(repo_root)
    roots = parse_roots_from_config(cfg, repo_root)
    print(f"Raíz del repo detectada: {repo_root}")
    print("Orígenes a auditar:")
    for r in roots:
        print(f"  - {r}")

    any_issue_as_error = False
    audited_any = False

    # Compilar caracteres especiales una sola vez
    special_chars_re = compile_special_chars_pattern(cfg, repo_root)

    for root_dir in roots:
        root_dir = root_dir.resolve()
        if not root_dir.exists() or not root_dir.is_dir():
            print(f"⚠️  Origen no válido (se omite): {root_dir}")
            continue

        audited_any = True
        for walk_root, _, files in os.walk(root_dir):
            # Ignora .github y .config en cualquier nivel
            parts = Path(walk_root).parts
            if ".github" in parts or ".config" in parts:
                continue

            for name in files:
                if not name.lower().endswith(".sql"):
                    continue
                full = Path(walk_root, name).resolve()
                rel_print = str(full)

                # Tamaño máximo de archivo (MB)
                try:
                    max_mb = float(cfg.get('paths','max_file_size_mb', fallback='5'))
                except Exception:
                    max_mb = 5.0
                size_mb = (full.stat().st_size / (1024*1024)) if full.exists() else 0
                if size_mb > max_mb:
                    # print(f"Se omite por tamaño ({size_mb:.2f} MB > {max_mb} MB): {rel_print}")
                    continue

                res = audit_file(full, cfg, special_chars_re)
                has_any = any([
                    res["nolock"], res["special"], res["global"], res["temp"],
                    res["curs"], res["funcs"], res["warn"], res["select_star"],
                    res["select_top"], res["top_without_order_by"], res["delete_update_without_where"],
                    res["merge_usage"], res["select_distinct_no_justification"],
                    res["exec_dynamic_sql_unparameterized"], res["select_into_heavy"],
                    res["scalar_udf_in_select_where"], res["deprecated_types"], res["hint_usage_general"]
                ])

                print(f"\n--- Archivo: {rel_print} ---")
                if not has_any:
                    print("   (sin hallazgos)")

                any_issue_as_error |= show("nolock", "Falta WITH (NOLOCK) en FROM/JOIN:", res["nolock"], cfg)
                any_issue_as_error |= show("special_chars", "Caracteres especiales no permitidos:", res["special"], cfg)
                any_issue_as_error |= show("global_temp", "Uso de tabla temporal global (##):", res["global"], cfg)
                any_issue_as_error |= show("temp_names", "Nombre de temporal genérico (#temp/@temp):", res["temp"], cfg)
                any_issue_as_error |= show("cursors", "Uso de cursor:", res["curs"], cfg)
                any_issue_as_error |= show("user_functions", "Función en WHERE:", res["funcs"], cfg)
                any_issue_as_error |= show("inner_join_where", "INNER JOIN + WHERE sin variantes:", res["warn"], cfg)
                any_issue_as_error |= show("select_star", "SELECT * detectado:", res["select_star"], cfg)
                any_issue_as_error |= show("select_top", "SELECT TOP detectado:", res["select_top"], cfg)

                any_issue_as_error |= show("top_without_order_by", "SELECT TOP sin ORDER BY:", res["top_without_order_by"], cfg)
                any_issue_as_error |= show("delete_update_without_where", "DELETE/UPDATE sin WHERE:", res["delete_update_without_where"], cfg)
                any_issue_as_error |= show("merge_usage", "MERGE detectado:", res["merge_usage"], cfg)
                any_issue_as_error |= show("select_distinct_no_justification", "SELECT DISTINCT sin justificación:", res["select_distinct_no_justification"], cfg)
                any_issue_as_error |= show("exec_dynamic_sql_unparameterized", "EXEC dinámico sin parámetros:", res["exec_dynamic_sql_unparameterized"], cfg)
                any_issue_as_error |= show("select_into_heavy", "SELECT INTO #temp (recomendación):", res["select_into_heavy"], cfg)

                any_issue_as_error |= show("scalar_udf_in_select_where", "UDF escalar en SELECT/WHERE:", res["scalar_udf_in_select_where"], cfg)
                any_issue_as_error |= show("deprecated_types", "Tipos deprecados (TEXT/NTEXT/IMAGE):", res["deprecated_types"], cfg)
                any_issue_as_error |= show("hint_usage_general", "Hints de consulta detectados:", res["hint_usage_general"], cfg)

    if not audited_any:
        print("\n⚠️  No se auditó ningún directorio (revisa [paths] sql_roots).")
        return

    if any_issue_as_error:
        print("\n❌ Se encontraron errores en uno o más archivos SQL")
        sys.exit(1)
    else:
        print("\n✅ Auditoría finalizada sin errores (sólo warnings o sin hallazgos).")

if __name__ == "__main__":
    main()
