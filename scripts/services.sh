#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
. scripts/helpers/menu.sh

compose_file=docker-compose.yaml
service_names=()
running=()
exact=1
menu_names=()
menu_lines=()
selected=()

fail() {
  printf 'Greska: %s\n' "$*" >&2
  exit 1
}

load_services() {
  local known running_list name i width=0 note deps
  local -a listed=()
  local -A deps_of=()
  command -v docker >/dev/null 2>&1 || fail 'Docker nije instaliran ili nije na PATH-u.'
  docker compose version >/dev/null 2>&1 || fail 'Docker Compose nije dostupan (docker compose version).'
  known=$(docker compose config --services) || fail "docker compose config nije uspeo; proverite $compose_file i .env."
  while IFS= read -r name; do
    if grep -qx -- "$name" <<< "$known"; then listed+=("$name"); fi
  done < <(awk '/^services:/ { s = 1; next } /^[^ #]/ { s = 0 } s && /^  [A-Za-z0-9_.-]+:/ { sub(/^  /, ""); sub(/:.*/, ""); print }' "$compose_file")
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    if ! printf '%s\n' "${listed[@]}" | grep -qx -- "$name"; then listed+=("$name"); fi
  done <<< "$known"
  (( ${#listed[@]} > 0 )) || fail "U $compose_file nema servisa."
  running_list=$(docker compose ps --services --status running 2>/dev/null || true)
  if command -v python3 >/dev/null 2>&1; then
    while IFS=' ' read -r name deps; do deps_of[$name]=$deps; done < <(docker compose config --format json 2>/dev/null | python3 -I -c '
import json, sys
for name, svc in json.load(sys.stdin)["services"].items():
    print(name, ", ".join(sorted((svc.get("depends_on") or {}).keys())))' 2>/dev/null || true)
  fi
  for ((i = 0; i < ${#listed[@]}; i++)); do
    service_names[i]=${listed[i]}
    running[i]=0
    if grep -qx -- "${listed[i]}" <<< "$running_list"; then running[i]=1; fi
    selected[i]=${running[i]}
    if (( ${#listed[i]} > width )); then width=${#listed[i]}; fi
  done
  menu_names=("${service_names[@]}")
  for ((i = 0; i < ${#service_names[@]}; i++)); do
    note=''
    if (( running[i] )); then note='(radi)'; fi
    deps=''
    if [[ -n ${deps_of[${service_names[i]}]:-} ]]; then deps="zavisi od: ${deps_of[${service_names[i]}]}"; fi
    menu_lines[i]=$(printf '%2d. %-*s  %-6s  %s' "$(( i + 1 ))" "$width" "${service_names[i]}" "$note" "$deps")
  done
}

print_services() {
  local i
  printf 'Servisi iz %s:\n' "$compose_file"
  for ((i = 0; i < ${#service_names[@]}; i++)); do printf '%s\n' "${menu_lines[i]}"; done
}

apply_selection() {
  local i
  local -a up=() start=() stop=()
  for ((i = 0; i < ${#service_names[@]}; i++)); do
    if (( selected[i] )); then
      up+=("${service_names[i]}")
      (( running[i] )) || start+=("${service_names[i]}")
    elif (( running[i] && exact )); then
      stop+=("${service_names[i]}")
    fi
  done
  if (( ${#up[@]} == 0 && ${#stop[@]} == 0 )); then
    printf 'Nijedan servis nije odabran; nista nije promenjeno.\n'
    return
  fi
  if (( ${#stop[@]} > 0 )); then
    printf 'Zaustavljam: %s\n' "${stop[*]}"
    docker compose stop "${stop[@]}"
  fi
  if (( ${#start[@]} > 0 )); then
    printf 'Podizem: %s\n' "${start[*]}"
  elif (( ${#up[@]} > 0 )); then
    printf 'Odabrani servisi vec rade; primenjujem eventualne izmene konfiguracije.\n'
  fi
  if (( ${#up[@]} > 0 )); then
    if (( exact )); then
      docker compose up -d --no-deps "${up[@]}"
    else
      docker compose up -d "${up[@]}"
    fi
  fi
  printf '\n'
  docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
}

services() {
  local i
  load_services
  if (( $# > 0 )); then
    for ((i = 0; i < ${#service_names[@]}; i++)); do selected[i]=0; done
    exact=0
    menu_select_from_args "$@" || exit 1
  elif [[ -t 0 && -t 1 ]]; then
    menu_select_interactive "Servisi iz $compose_file. Posle Enter rade tacno oznaceni: odznaceni koji rade se zaustavljaju, zavisnosti se ne dodaju same." || { printf 'Odustali ste; nista nije promenjeno.\n'; exit 0; }
  else
    print_services
    fail 'Terminal nije interaktivan. Navedite servise za podizanje: task services -- k-fakture k-gateway, task services -- 1 3, ili task services -- all.'
  fi
  apply_selection
}

services "$@"
