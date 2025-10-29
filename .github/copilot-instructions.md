## Instrucciones rápidas para agentes de IA (Copilot/Agents)

Este repositorio es una plantilla para auditoría automática de código SQL mediante GitHub Actions. El propósito de este documento es dar al agente el contexto mínimo necesario para ser productivo inmediatamente.

- Resumen del propósito: Auditar archivos `*.sql` en el repositorio contra un conjunto de reglas (NOLOCK, SELECT *, cursores, caracteres especiales, nombres temporales, funciones de usuario, etc.) y reportar resultados como errores/advertencias en GitHub Actions.

Entradas / Salidas (contrato rápido)
- Input: Código fuente del repo (principalmente `.sql`) y archivo de configuración en `.github/audit/audit_config.ini`.
- Output: Informes de auditoría (console / Actions), códigos de salida según severidad (error = falla de job; warning = no falla).

Puntos críticos y arquitectura (qué mirar)
- Carpeta principal de reglas y workflows: `.github/audit/` y `.github/workflows/` (según el README). Archivos clave según README:
  - `.github/audit/audit_sql_standards.py` — script principal de auditoría.
  - `.github/audit/audit_config.ini` — define qué reglas están activas y sus severidades.
  - `.github/audit/special_chars.txt` — caracteres prohibidos detectados por una regla.
  - `.github/workflows/sql-audit.yml` — workflow que ejecuta la auditoría en push/PR.
  - `.github/workflows/guard-dotgithub.yml` — protege cambios directos en `.github/`.

¿Qué busca el auditor? (ejemplos concretos desde README)
- WITH (NOLOCK) ausente en FROM/JOIN (ignorando tablas temporales y sysobjects).
- SELECT * o SELECT TOP * (marcado como error o warning según config).
- DECLARE ... CURSOR — detección de cursores.
- Llamadas a funciones de usuario en WHERE (ej. `dbo.CalculaDescuento(...)`).
- Caracteres especiales listados en `special_chars.txt`.

Convenciones del proyecto (detectables)
- Las reglas están controladas por `.github/audit/audit_config.ini` en secciones `[rules]` y `[severities]`.
- Rutas escaneadas: la configuración `sql_roots` (en README muestra `.` por defecto) ignora `.github`.
- Severidad: `error` hará fallar el workflow (bloquea merge), `warning` solo reporta.

Flujos de trabajo y comandos útiles (asumidos a partir del README)
- No hay build tradicional; para ejecutar la auditoría localmente (asunción razonable):
  - `python .github/audit/audit_sql_standards.py --paths . --config .github/audit/audit_config.ini`
  - Nota: si el script no acepta exactamente esos flags, busca la cabecera del script en `.github/audit/` y adapta los parámetros.

Patrones y ejemplos en el repo
- Archivos SQL presentes ahora: `test1.sql`, `Untitled-1.sql`, `Untitled-2.sql` — úsalos como ejemplos de entrada para pruebas rápidas.
- Usa el README.md (raíz) como referencia de comportamiento esperado y ejemplos de mensajes de error/advertencia.

Reglas para el agente (qué hacer / qué evitar)
- Hacer: Prioriza ejecutar/validar reglas reproducibles y extraer la configuración desde `.github/audit/audit_config.ini` cuando exista.
- Hacer: Referenciar líneas concretas en los archivos `.sql` al reportar hallazgos (formato: Archivo + número de línea + mensaje breve).
- Evitar: Proponer cambios estructurales grandes sin indicación del propietario; para cambios en `.github/`, respeta la política de CODEOWNERS mencionada en el README.

Notas sobre inconsistencia posible
- Este repositorio es una plantilla: el README documenta archivos bajo `.github/` que podrían no estar presentes todavía. Si un archivo documentado no existe, anota la ausencia y sugiere una ruta o plantilla basada en el README.

Referencias rápidas en el repo
- `README.md` (raíz) — descripción de reglas y ejemplos.
- `/test1.sql`, `/Untitled-1.sql`, `/Untitled-2.sql` — ejemplos de SQL en la rama actual.

Si necesitas más detalles
- Pide al mantenedor: confirmar la presencia/versión del script `.github/audit/audit_sql_standards.py` y el formato exacto de `audit_config.ini` si quieres ejecutar la auditoría localmente.

¿Feedback?
- He creado/actualizado este archivo con la información detectada. Dime si quieres que incluya ejemplos concretos de mensajes de error o adaptar los comandos locales a la invocación exacta del script (si lo añades al repo).
