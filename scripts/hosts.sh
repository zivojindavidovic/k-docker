#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
. scripts/helpers/domains.sh

linux_hosts=/etc/hosts
windows_hosts=/mnt/c/Windows/System32/drivers/etc/hosts

is_wsl() {
  [[ -n ${WSL_DISTRO_NAME:-} ]] || grep -qi microsoft /proc/version 2>/dev/null
}

hosts_has() {
  awk -v h="$2" '
    { sub(/\r$/, ""); sub(/#.*/, ""); for (i = 2; i <= NF; i++) if (tolower($i) == tolower(h)) found = 1 }
    END { exit !found }' "$1" 2>/dev/null
}

add_hosts_linux() {
  local file=$linux_hosts missing=() h payload=''
  [[ -r $file ]] || { printf 'Greska: %s nije citljiv.\n' "$file" >&2; return 1; }
  for h; do hosts_has "$file" "$h" || missing+=("$h"); done
  if (( ${#missing[@]} == 0 )); then
    printf '%s: svi lokalni domeni su vec upisani.\n' "$file"
    return 0
  fi
  if [[ -s $file && -n $(tail -c 1 "$file") ]]; then payload=$'\n'; fi
  for h in "${missing[@]}"; do payload+="127.0.0.1 $h"$'\n'; done
  if [[ -w $file ]]; then
    printf '%s' "$payload" >> "$file" || return 1
  else
    command -v sudo >/dev/null 2>&1 || { printf 'Greska: sudo nije dostupan, %s nije izmenjen.\n' "$file" >&2; return 1; }
    printf 'Upis u %s zahteva administratorska prava; unesite sudo lozinku ako je zatrazi.\n' "$file"
    printf '%s' "$payload" | sudo tee -a "$file" > /dev/null || return 1
  fi
  for h in "${missing[@]}"; do hosts_has "$file" "$h" || return 1; done
  printf 'Dodato u %s: %s\n' "$file" "${missing[*]}"
}

add_hosts_windows() {
  local file=$windows_hosts missing=() h values='' script encoded winfile
  [[ -r $file ]] || { printf 'Greska: Windows hosts fajl %s nije dostupan iz WSL-a.\n' "$file" >&2; return 1; }
  for h; do hosts_has "$file" "$h" || missing+=("$h"); done
  if (( ${#missing[@]} == 0 )); then
    printf 'Windows hosts: svi lokalni domeni su vec upisani.\n'
    return 0
  fi
  command -v powershell.exe >/dev/null 2>&1 || { printf 'Greska: powershell.exe nije dostupan iz WSL-a; proverite Windows interop.\n' >&2; return 1; }
  winfile=$(wslpath -w "$file") || return 1
  for h in "${missing[@]}"; do values+="'127.0.0.1 $h',"; done
  values=${values%,}
  script="\$ErrorActionPreference='Stop'; \$p='$winfile'; \$c=[IO.File]::ReadAllText(\$p); if(\$c.Length -gt 0 -and -not \$c.EndsWith(\"\`n\")){[IO.File]::AppendAllText(\$p,\"\`r\`n\")}; Add-Content -LiteralPath \$p -Value $values -Encoding ascii"
  encoded=$(printf '%s' "$script" | iconv -f UTF-8 -t UTF-16LE | base64 -w 0) || return 1
  printf 'Upis u Windows hosts zahteva administratorska prava; potvrdite UAC prozor na Windows-u.\n'
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "\$ErrorActionPreference='Stop'; \$p = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand','$encoded'; exit \$p.ExitCode" || return 1
  for h in "${missing[@]}"; do hosts_has "$file" "$h" || return 1; done
  printf 'Dodato u Windows hosts (%s): %s\n' "$winfile" "${missing[*]}"
}

hosts() {
  local failed=0 h
  local -a domains
  mapfile -t domains < <(local_domains)
  (( ${#domains[@]} > 0 )) || return 0
  add_hosts_linux "${domains[@]}" || failed=1
  if is_wsl; then
    add_hosts_windows "${domains[@]}" || failed=1
  fi
  if (( failed )); then
    printf 'Dodajte rucno u /etc/hosts (Linux/WSL) i u C:\\Windows\\System32\\drivers\\etc\\hosts (Windows, kao administrator):\n' >&2
    for h in "${domains[@]}"; do printf '  127.0.0.1 %s\n' "$h" >&2; done
    return 1
  fi
}

hosts
