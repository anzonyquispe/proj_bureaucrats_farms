#!/usr/bin/env bash
# Fail if any reghdfejl call lacks an explicit tolerance(1e-6).
#
# The paper's estimates use reghdfejl's pre-1.1.6 default tolerance (1e-6);
# newer versions default to 1e-8, and specifications with cohort-specific
# province trends change with the tolerance. Writing the option in every call
# keeps the results independent of the installed version.
#
# Usage: check_tolerance.sh PATH [PATH ...]
#   PATH is a dofile or a directory searched recursively for *.do files.

set -euo pipefail

files=()
for target in "$@"; do
  if [[ -d "${target}" ]]; then
    while IFS= read -r file; do files+=("${file}"); done \
      < <(find "${target}" -name '*.do' | sort)
  else
    files+=("${target}")
  fi
done
(( ${#files[@]} == 0 )) && exit 0

violations=$(awk '
  FNR == 1 { inblock = 0; stmt = "" }
  {
    sub(/\r$/, "")
    line = $0
    code = ""
    # Remove /* */ comments, which may span lines.
    while (line != "") {
      if (inblock) {
        p = index(line, "*/")
        if (p == 0) { line = "" } else { line = substr(line, p + 2); inblock = 0 }
      } else {
        p = index(line, "/*")
        if (p == 0) { code = code line; line = "" }
        else { code = code substr(line, 1, p - 1); line = substr(line, p + 2); inblock = 1 }
      }
    }
    if (stmt == "") {
      start = FNR
      if (code ~ /^[ \t]*\*/) next
    }
    # /// continues the statement on the next line; // ends it with a comment.
    if (match(code, /(^|[ \t])\/\/\//)) {
      stmt = stmt substr(code, 1, RSTART - 1) " "
      next
    }
    if (match(code, /(^|[ \t])\/\//)) code = substr(code, 1, RSTART - 1)
    stmt = stmt code
    if (stmt ~ /^[ \t]*((qui|quietly|cap|capture|noi|noisily)[ \t]+)*reghdfejl([ \t,]|$)/ &&
        stmt !~ /tol(erance)?\([ \t]*1e-0?6[ \t]*\)/)
      print FILENAME ":" start
    stmt = ""
  }
' "${files[@]}")

if [[ -n "${violations}" ]]; then
  echo "ERROR: reghdfejl calls without tolerance(1e-6):" >&2
  printf '%s\n' "${violations}" | sed 's/^/  /' >&2
  exit 65
fi
