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
    # Normaliza y filtra duplicados.
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
}

def sev(cfg: configparser.ConfigParser, rule: str) -> str:
    s = cfg.get("severities", rule, fallback=DEFAULT_SEVERITIES.get(rule, "error")).lower()
    return "off" if s not in {"error", "warning", "off"} else s

def badge(severity: str) -> str:
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

# sys.* y sysobjects (excepción en NOLOCK)
def is_sys_table(token: str) -> bool:
    t = token.strip().strip("[]")
    low = t.lower()
    # Casos: "sysobjects", "sys.objects", "sys.sysobjects", etc.
    if low == "sysobjects":
        return True
    parts = [p.strip("[]").lower() for p in t.split(".")]
    if parts and parts[0] == "sys":
        return True
    return False

# -----------------------------
# Carga de caracteres especiales
# -----------------------------
def compile_special_chars_pattern(cfg: configparser.ConfigParser, repo_root: Path) -> re.Pattern:
    rel = cfg.get("paths", "special_chars_file", fallback=".github/audit/special_chars.txt").strip()
    path = (repo_root / rel) if not Path(rel).is_absolute() else Path(rel)
    chars: list[str] = []
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
# Reglas (modular)
# -----------------------------
def rule_enabled(cfg: configparser.ConfigParser, key: str, default: bool = True) -> bool:
    return cfg.getboolean("rules", key, fallback=default)

def check_nolock(lines):
    issues=[]
    for i,ln in enumerate(lines,1):
        l=ln.strip()
        if l.startswith('--') or ignore_temp_tables_pattern.search(ln):
            continue
        # Si la línea ya tiene NOLOCK, ok
        if nolock_pattern.search(ln) or nolock_paren_only_pattern.search(ln):
            continue
        m = re.search(r"\b(FROM|JOIN)\s+([\w.\[\]]+)", ln, re.IGNORECASE)
        if m:
            table = m.group(2)
            # Excepción: tablas del sistema (sys.*, sysobjects)
            if is_sys_table(table):
                continue
            # Ignorar temporales/variables
            if re.match(r"[#@]", table):
                continue
            issues.append(f"   Línea {i}: Falta hint WITH (NOLOCK) en {m.group(1).upper()} tabla '{table}'")
    return issues

def check_special_chars(lines, special_chars_re: re.Pattern):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines,1) if special_chars_re.search(ln)]

def check_global_temp(lines):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines,1)
            if not ln.strip().startswith('--') and global_temp_pattern.search(ln)]

def check_temp_names(lines):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines,1)
            if not ln.strip().startswith('--') and bad_temp_names_pattern.search(ln)]

def check_cursors(lines):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines,1)
            if not ln.strip().startswith('--') and cursor_pattern.search(ln)]

def check_user_funcs(lines):
    issues=[]
    for i,ln in enumerate(lines,1):
        l=ln.strip()
        if l.startswith('--'): 
            continue
        if user_function_in_where_pattern.search(ln):
            issues.append(f"   Línea {i}: {l}")
    return issues

def check_inner_join_warnings(lines):
    issues=[]
    join_count=0; first_join=None; has_variant=False; in_block=False
    for i,ln in enumerate(lines,1):
        line = ln.strip()
        if not line or line.startswith('--'):
            continue
        if re.search(r"\bSELECT\b", line, re.IGNORECASE):
            join_count=0; first_join=None; has_variant=False; in_block=True
        if not in_block:
            continue
        if re.search(r"\bINNER\s+JOIN\b", line, re.IGNORECASE):
            join_count+=1
            if first_join is None:
                first_join=i
        if re.search(r"\b(LEFT|RIGHT|FULL|OUTER)\s+JOIN\b", line, re.IGNORECASE):
            has_variant=True
        if re.search(r"\bWHERE\b", line, re.IGNORECASE):
            if join_count>1 and not has_variant and first_join is not None:
                issues.append(f"   Línea {first_join}: Múltiples INNER JOIN + WHERE sin variantes")
            in_block=False; join_count=0; has_variant=False; first_join=None
        if re.search(r";\s*$", line):
            in_block=False; join_count=0; has_variant=False; first_join=None
    return issues

# --- Nuevas reglas ---
def check_select_star(lines):
    """
    Detecta SELECT * (aunque esté partido en varias líneas).
    Lógica: acumula desde SELECT hasta FROM y evalúa el "cláusula de selección".
    """
    issues=[]
    buffering=False
    buf=[]; start_line=None
    for i,ln in enumerate(lines,1):
        raw = ln
        line = ln.split("--",1)[0]  # quita comentario hasta fin de línea
        if not buffering and re.search(r"\bSELECT\b", line, re.IGNORECASE):
            buffering=True
            start_line=i
            buf=[line]
            # ¿SELECT y FROM en misma línea?
            if re.search(r"\bFROM\b", line, re.IGNORECASE):
                buffering=False
                joined=" ".join(buf)
                m=re.search(r"\bSELECT\b(?P<clause>.*?)\bFROM\b", joined, re.IGNORECASE|re.DOTALL)
                if m:
                    clause = m.group("clause")
                    if re.fullmatch(r"\s*\*\s*", clause, re.DOTALL):
                        issues.append(f"   Línea {start_line}: Uso de SELECT *")
                buf=[]
            continue

        if buffering:
            buf.append(line)
            if re.search(r"\bFROM\b", line, re.IGNORECASE):
                buffering=False
                joined=" ".join(buf)
                m=re.search(r"\bSELECT\b(?P<clause>.*?)\bFROM\b", joined, re.IGNORECASE|re.DOTALL)
                if m:
                    clause = m.group("clause")
                    if re.fullmatch(r"\s*\*\s*", clause, re.DOTALL):
                        issues.append(f"   Línea {start_line}: Uso de SELECT *")
                buf=[]

    return issues

def check_select_top(lines):
    """
    Detecta uso de SELECT TOP (en la cláusula inmediatamente tras SELECT).
    """
    issues=[]
    buffering=False
    buf=[]; start_line=None
    for i,ln in enumerate(lines,1):
        line = ln.split("--",1)[0]
        if not buffering and re.search(r"\bSELECT\b", line, re.IGNORECASE):
            buffering=True
            start_line=i
            buf=[line]
            if re.search(r"\bFROM\b", line, re.IGNORECASE):
                buffering=False
                joined=" ".join(buf)
                m=re.search(r"\bSELECT\b(?P<clause>.*?)\bFROM\b", joined, re.IGNORECASE|re.DOTALL)
                if m and re.search(r"\bTOP\b", m.group("clause"), re.IGNORECASE):
                    issues.append(f"   Línea {start_line}: Uso de SELECT TOP")
                buf=[]
            continue

        if buffering:
            buf.append(line)
            if re.search(r"\bFROM\b", line, re.IGNORECASE):
                buffering=False
                joined=" ".join(buf)
                m=re.search(r"\bSELECT\b(?P<clause>.*?)\bFROM\b", joined, re.IGNORECASE|re.DOTALL)
                if m and re.search(r"\bTOP\b", m.group("clause"), re.IGNORECASE):
                    issues.append(f"   Línea {start_line}: Uso de SELECT TOP")
                buf=[]
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
        "select_star": [], "select_top": []
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

    return res

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

                res = audit_file(full, cfg, compile_special_chars_pattern(cfg, repo_root))
                has_any = any([res["nolock"], res["special"], res["global"], res["temp"],
                               res["curs"], res["funcs"], res["warn"], res["select_star"], res["select_top"]])
                if not has_any:
                    continue

                print(f"\n📄 Archivo: {rel_print}")

                # Muestra por regla según severidad y levanta bandera de error si corresponde
                def show(rule_key: str, title: str, items: list[str]):
                    if not items:
                        return
                    severity = sev(cfg, rule_key)
                    if severity == "off":
                        return
                    print(f"{badge(severity)} {title}")
                    for it in items:
                        print(it)
                    if severity == "error":
                        nonlocal any_issue_as_error
                        any_issue_as_error = True

                show("nolock", "NOLOCK ausente:", res["nolock"])
                show("special_chars", "Caracteres especiales encontrados:", res["special"])
                show("global_temp", "Uso de tablas globales (##):", res["global"])
                show("temp_names", "Nombres genéricos en tablas temporales:", res["temp"])
                show("cursors", "Uso de cursores:", res["curs"])
                show("user_functions", "Funciones de usuario dentro del WHERE:", res["funcs"])
                show("inner_join_where", "INNER JOIN + WHERE sin variantes:", res["warn"])
                show("select_star", "SELECT * detectado:", res["select_star"])
                show("select_top", "SELECT TOP detectado:", res["select_top"])

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
