import os
import re
import sys
from pathlib import Path
from datetime import datetime
import configparser

# -----------------------------
# Utilidades de rutas & config
# -----------------------------

CONFIG_DIR_NAMES = {".config", "config"}

def is_in_config_dir(path: str) -> bool:
    """True si la ruta está dentro de /config o /.config (en cualquier nivel)."""
    parts = Path(path).resolve().parts
    return any(part in CONFIG_DIR_NAMES for part in parts)

def find_repo_root(start: Path) -> Path:
    """Detecta la raíz del repo buscando un dir config/.config cerca."""
    for p in [start] + list(start.parents):
        for cfg_name in CONFIG_DIR_NAMES:
            if (p / cfg_name).exists() and (p / cfg_name).is_dir():
                return p if p.name not in CONFIG_DIR_NAMES else p.parent
    return start if start.name not in CONFIG_DIR_NAMES else start.parent

def find_config_file(start: Path) -> Path | None:
    """Busca audit_config.ini dentro de config o .config desde la raíz del repo."""
    repo = find_repo_root(start)
    for cfg_name in CONFIG_DIR_NAMES:
        candidate = repo / cfg_name / "audit_config.ini"
        if candidate.exists():
            return candidate
    return None

def load_config(start: Path) -> configparser.ConfigParser:
    cfg = configparser.ConfigParser()
    cfg_path = find_config_file(start)
    if cfg_path:
        cfg.read(cfg_path, encoding="utf-8")
    return cfg

def parse_roots_from_config(cfg: configparser.ConfigParser, repo_root: Path) -> list[Path]:
    """
    Lee [paths] sql_roots. Soporta coma o ';'. Si no hay valor, audita toda la repo.
    """
    if not cfg.has_section("paths"):
        return [repo_root]
    raw = cfg.get("paths", "sql_roots", fallback="").strip()
    if not raw:
        return [repo_root]

    parts = []
    for token in raw.replace(";", ",").split(","):
        token = token.strip()
        if token:
            parts.append(token)

    cleaned: list[Path] = []
    for p in parts:
        pp = Path(p)
        abs_p = pp if pp.is_absolute() else (repo_root / pp)
        if abs_p not in cleaned:
            cleaned.append(abs_p)
    return cleaned or [repo_root]

# -----------------------------
# Logging sencillo a archivo
# -----------------------------

class Logger:
    def __init__(self, enabled: bool, log_path: Path | None, also_console: bool, level: str = "INFO"):
        self.enabled = enabled
        self.also_console = also_console
        self.level = level.upper()
        self.fp = None
        if self.enabled and log_path is not None:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            self.fp = open(log_path, "w", encoding="utf-8", newline="\n")
            self._write(f"[{self.level}] Log iniciado: {datetime.now().isoformat(timespec='seconds')}")

    def _write(self, text: str) -> None:
        if self.fp:
            self.fp.write(text + "\n")
            self.fp.flush()

    def log(self, text: str) -> None:
        if self.also_console:
            print(text)
        if self.enabled:
            self._write(text)

    def close(self):
        if self.fp:
            self._write(f"[{self.level}] Log finalizado: {datetime.now().isoformat(timespec='seconds')}")
            self.fp.close()
            self.fp = None

def build_logger(cfg: configparser.ConfigParser, repo_root: Path) -> Logger:
    enabled = cfg.getboolean("log", "enabled", fallback=True)
    also_console = cfg.getboolean("log", "also_console", fallback=True)
    level = cfg.get("log", "level", fallback="INFO")

    logs_dir_cfg = cfg.get("paths", "logs_dir", fallback="config/audit_logs")
    logs_dir = (repo_root / logs_dir_cfg) if not Path(logs_dir_cfg).is_absolute() else Path(logs_dir_cfg)
    logs_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("audit_%Y-%m-%d_%H-%M-%S.log")
    log_path = logs_dir / stamp
    return Logger(enabled, log_path, also_console, level)

# -----------------------------
# Carga de caracteres especiales
# -----------------------------

def compile_special_chars_pattern(cfg: configparser.ConfigParser, repo_root: Path) -> re.Pattern:
    """
    Lee la lista de caracteres no permitidos desde config/special_chars.txt (uno por línea).
    Si el archivo no existe o está vacío, usa un conjunto básico por defecto.
    """
    rel_path = cfg.get("paths", "special_chars_file", fallback="config/special_chars.txt").strip()
    path = (repo_root / rel_path) if not Path(rel_path).is_absolute() else Path(rel_path)
    chars: list[str] = []
    if path.exists():
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                s = raw.strip()
                if not s or s.startswith("#"):
                    continue
                # admite líneas de longitud > 1 por si el usuario pone símbolos compuestos; tomamos literal
                chars.append(s)
    if not chars:
        # Fallback básico
        chars = list("áéíóúÁÉÍÓÚñÑ&%$¡¿")

    # Construimos una clase de caracteres. Para tokens largos, mejor unir con |.
    # Si todas las líneas son un solo carácter, usamos clase; si hay tokens multicaracter, usamos alternación.
    if all(len(c) == 1 for c in chars):
        # clase de caracteres
        escaped = "".join(re.escape(c) for c in chars)
        return re.compile(f"[{escaped}]")
    else:
        # alternación de tokens (respetando orden por longitud descendente para evitar backtracking)
        chars.sort(key=len, reverse=True)
        alt = "|".join(re.escape(c) for c in chars)
        return re.compile(alt, re.IGNORECASE)

# -----------------------------
# Reglas (toggles desde config)
# -----------------------------

def rule_enabled(cfg: configparser.ConfigParser, key: str, default: bool = True) -> bool:
    return cfg.getboolean("rules", key, fallback=default)

# Patrones comunes (los que no dependen de config)
nolock_pattern = re.compile(r"(WITH\s*)?\(\s*NOLOCK\s*(,\s*READUNCOMMITTED\s*)?\)", re.IGNORECASE)
nolock_paren_only_pattern = re.compile(r"\(\s*NOLOCK\s*(,\s*READUNCOMMITTED\s*)?\)", re.IGNORECASE)
ignore_temp_tables_pattern = re.compile(r"FROM\s+[#@]{1,2}[\w\d_]+", re.IGNORECASE)
global_temp_pattern = re.compile(r"##\w+", re.IGNORECASE)
bad_temp_names_pattern = re.compile(r"(#temp|@temp)", re.IGNORECASE)
cursor_pattern = re.compile(r"\bCURSOR\b", re.IGNORECASE)
# Invocación a funciones como componentes: dbo.Algo(...), schema.Func(...)
user_function_in_where_pattern = re.compile(
    r"WHERE\s+.*?\b(?:dbo|db|schema|owner)\.\w+\s*\(.*?\)",
    re.IGNORECASE
)

# -----------------------------
# Chequeos (mantenemos modular)
# -----------------------------

def check_nolock(lines):
    issues = []
    for i, ln in enumerate(lines, 1):
        l = ln.strip()
        if l.startswith('--') or ignore_temp_tables_pattern.search(ln):
            continue
        if not (nolock_pattern.search(ln) or nolock_paren_only_pattern.search(ln)):
            m = re.search(r"\b(FROM|JOIN)\s+([\w.\[\]]+)", ln, re.IGNORECASE)
            if m and not re.match(r"[#@]", m.group(2)):
                issues.append(f"   Línea {i}: Falta hint WITH (NOLOCK) en {m.group(1).upper()} tabla '{m.group(2)}'")
    return issues

def check_special_chars(lines, special_chars_re: re.Pattern):
    return [f"   Línea {i}: {ln.strip()}" for i, ln in enumerate(lines, 1)
            if special_chars_re.search(ln)]

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
    """Detecta invocaciones a funciones de componentes (dbo.XYZ(...)) dentro de WHERE."""
    issues = []
    for i, ln in enumerate(lines, 1):
        l = ln.strip()
        if l.startswith('--'):
            continue
        if user_function_in_where_pattern.search(ln):
            issues.append(f"   Línea {i}: {l}")
    return issues

def check_inner_join_warnings(lines):
    """
    Warning cuando en el MISMO SELECT hay:
    - más de un INNER JOIN
    - aparece WHERE
    - y NO hay variantes de JOIN (LEFT/RIGHT/FULL/OUTER) en ese mismo bloque.
    """
    issues = []
    join_count = 0
    first_join_line = None
    has_variant = False
    in_block = False

    for i, ln in enumerate(lines, 1):
        line = ln.strip()
        if not line or line.startswith('--'):
            continue

        if re.search(r"\bSELECT\b", line, re.IGNORECASE):
            join_count = 0
            first_join_line = None
            has_variant = False
            in_block = True

        if not in_block:
            continue

        if re.search(r"\bINNER\s+JOIN\b", line, re.IGNORECASE):
            join_count += 1
            if first_join_line is None:
                first_join_line = i

        if re.search(r"\b(LEFT|RIGHT|FULL|OUTER)\s+JOIN\b", line, re.IGNORECASE):
            has_variant = True

        if re.search(r"\bWHERE\b", line, re.IGNORECASE):
            if join_count > 1 and not has_variant and first_join_line is not None:
                issues.append(f"   Línea {first_join_line}: Múltiples INNER JOIN + WHERE sin variantes")
            in_block = False
            join_count = 0
            has_variant = False
            first_join_line = None

        if re.search(r";\s*$", line):
            in_block = False
            join_count = 0
            has_variant = False
            first_join_line = None

    return issues

def audit_file(fp, cfg: configparser.ConfigParser, special_chars_re: re.Pattern):
    with open(fp, encoding='utf-8') as f:
        lines = f.read().splitlines(True)

    res = {"archivo": fp, "nolock": [], "special": [], "global": [], "temp": [], "curs": [], "funcs": [], "warn": []}

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

    return res

def main():
    start = Path.cwd()
    repo_root = find_repo_root(start)
    cfg = load_config(start)
    logger = build_logger(cfg, repo_root)
    special_chars_re = compile_special_chars_pattern(cfg, repo_root)
    roots = parse_roots_from_config(cfg, repo_root)

    logger.log("==== Auditoría iniciada ====\n")
    logger.log(f"Raíz del repo detectada: {repo_root}")
    logger.log("Orígenes a auditar:")
    for r in roots:
        logger.log(f"  - {r}")

    total_files_with_issues = 0
    audited_any = False

    for root_dir in roots:
        root_dir = root_dir.resolve()
        if not root_dir.exists() or not root_dir.is_dir():
            logger.log(f"⚠️  Origen no válido (se omite): {root_dir}")
            continue

        logger.log(f"\nEscaneando *.sql recursivamente en: {root_dir}")
        audited_any = True

        for root, _, files in os.walk(root_dir):
            if is_in_config_dir(root):
                continue
            for file in files:
                if not file.lower().endswith(".sql"):
                    continue
                full_path = os.path.join(root, file)
                if is_in_config_dir(full_path):
                    continue

                rel = os.path.relpath(full_path, repo_root)
                logger.log(f"📄 Analizando: {rel}")

                res = audit_file(full_path, cfg, special_chars_re)
                has_any = any([res["nolock"], res["special"], res["global"], res["temp"], res["curs"], res["funcs"], res["warn"]])
                if has_any:
                    logger.log(f"\n📄 Archivo: {rel}")
                    if res["nolock"]:
                        logger.log("❌ NOLOCK ausente:"); logger.log("\n".join(res["nolock"]))
                    if res["special"]:
                        logger.log("❌ Caracteres especiales encontrados:"); logger.log("\n".join(res["special"]))
                    if res["global"]:
                        logger.log("❌ Uso de tablas globales (##):"); logger.log("\n".join(res["global"]))
                    if res["temp"]:
                        logger.log("❌ Nombres genéricos en tablas temporales:"); logger.log("\n".join(res["temp"]))
                    if res["curs"]:
                        logger.log("❌ Uso de cursores:"); logger.log("\n".join(res["curs"]))
                    if res["funcs"]:
                        logger.log("❌ Funciones de usuario dentro del WHERE:"); logger.log("\n".join(res["funcs"]))
                    if res["warn"]:
                        logger.log("❌ INNER JOIN + WHERE sin variantes:"); logger.log("\n".join(res["warn"]))
                    total_files_with_issues += 1

    if not audited_any:
        logger.log("\n⚠️  No se auditó ningún directorio (revisa [paths] sql_roots en config/audit_config.ini).")
        logger.close()
        return

    if total_files_with_issues > 0:
        logger.log(f"\n❌ Se encontraron errores en {total_files_with_issues} archivo(s) SQL")
        logger.close()
        sys.exit(1)
    else:
        logger.log("✅ Auditoría finalizada sin errores.")
        logger.close()

if __name__ == "__main__":
    main()
