#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
. scripts/helpers/menu.sh
. scripts/helpers/domains.sh

compose_file=docker-compose.yaml
required_services=(k-local k-auth k-auth-worker k-gateway k-master-db k-license-1-db k-redis)
service_names=()
states=()
exact=1
name_width=0
stop_all=-1
saved_selection=()
menu_names=()
menu_lines=()
menu_locked=()
menu_divider=()
selected=()
declare -A deps_of=()
declare -A index_of=()

if (( menu_utf8 )); then
  sym_running='●' sym_stopped='○' sym_start='↑' sym_stop='↓' sym_warn='⚠'
else
  sym_running='*' sym_stopped='-' sym_start='+' sym_stop='x' sym_warn='!'
fi

fail() {
  printf 'Greska: %s\n' "$*" >&2
  exit 1
}

contains() {
  local needle=$1 item
  shift
  for item; do
    if [[ $item == "$needle" ]]; then return 0; fi
  done
  return 1
}

service_keys() {
  awk '/^services:/ { s = 1; next } /^[^ #]/ { s = 0 } s && /^  [A-Za-z0-9_.-]+:/ { sub(/^  /, ""); sub(/:.*/, ""); print }'
}

is_active() {
  [[ $1 != stopped ]]
}

stopping_all() {
  (( stop_all >= 0 && selected[stop_all] ))
}

load_states() {
  local list name state health i
  local -A found=()
  list=$(docker compose ps -a --format $'{{.Service}}\t{{.State}}\t{{.Health}}') || fail 'docker compose ps nije uspeo.'
  while IFS=$'\t' read -r name state health; do
    [[ -n $name ]] || continue
    case $state in
      running)
        case $health in
          starting | unhealthy) state=$health ;;
          *) state=running ;;
        esac
        ;;
      restarting | paused) ;;
      *) state=stopped ;;
    esac
    if [[ ${found[$name]:-stopped} == stopped ]]; then found[$name]=$state; fi
  done <<< "$list"
  for ((i = 0; i < ${#service_names[@]}; i++)); do states[i]=${found[${service_names[i]}]:-stopped}; done
}

load_services() {
  local config known name dep i
  command -v docker >/dev/null 2>&1 || fail 'Docker nije instaliran ili nije na PATH-u.'
  docker compose version >/dev/null 2>&1 || fail 'Docker Compose nije dostupan (docker compose version).'
  config=$(docker compose config) || fail "docker compose config nije uspeo; proverite $compose_file i .env."
  known=$(service_keys <<< "$config")
  while IFS= read -r name; do
    if grep -qx -- "$name" <<< "$known" && ! contains "$name" "${service_names[@]}"; then service_names+=("$name"); fi
  done < <(service_keys < "$compose_file")
  while IFS= read -r name; do
    if [[ -n $name ]] && ! contains "$name" "${service_names[@]}"; then service_names+=("$name"); fi
  done <<< "$known"
  (( ${#service_names[@]} > 0 )) || fail "U $compose_file nema servisa."
  while read -r name dep; do
    deps_of[$name]+="${deps_of[$name]:+ }$dep"
  done < <(awk '/^services:/ { s = 1; next } /^[^ ]/ { s = 0 }
    s && /^  [^ ]/ { svc = $1; sub(/:$/, "", svc); d = 0; next }
    s && /^    depends_on:/ { d = 1; next }
    s && d && /^      [^ ]/ { dep = $1; sub(/:$/, "", dep); print svc, dep; next }
    s && d && /^    [^ ]/ { d = 0 }' <<< "$config")
  load_states
  for ((i = 0; i < ${#service_names[@]}; i++)); do
    index_of[${service_names[i]}]=$i
    if (( ${#service_names[i]} > name_width )); then name_width=${#service_names[i]}; fi
    menu_locked[i]=0
    selected[i]=0
    if contains "${service_names[i]}" "${required_services[@]}"; then menu_locked[i]=1; fi
    if (( menu_locked[i] )) || is_active "${states[i]}"; then selected[i]=1; fi
  done
  menu_names=("${service_names[@]}")
  for ((i = 0; i < ${#service_names[@]}; i++)); do
    service_line "$i"
    menu_lines[i]=$REPLY
  done
}

status_text() {
  local mark=$sym_running color label
  case $1 in
    running) color=$c_green label='radi' ;;
    starting) color=$c_yellow label='startuje' ;;
    unhealthy) color=$c_red label='unhealthy' ;;
    restarting) color=$c_yellow label='restartuje se' ;;
    paused) color=$c_yellow label='pauziran' ;;
    *) color=$c_dim label='ne radi' mark=$sym_stopped ;;
  esac
  printf -v REPLY '%s%s %-13s%s' "$color" "$mark" "$label" "$c_reset"
}

service_line() {
  status_text "${states[$1]}"
  printf -v REPLY '%-*s  %s' "$name_width" "${service_names[$1]}" "$REPLY"
}

add_stop_all_row() {
  stop_all=${#service_names[@]}
  menu_names[stop_all]='Ugasi sve servise'
  menu_lines[stop_all]="${c_red}Ugasi sve servise$c_reset"
  menu_divider[stop_all]=1
  selected[stop_all]=0
}

menu_toggle() {
  local i
  if [[ $1 == "$stop_all" ]]; then
    if stopping_all; then
      selected=("${saved_selection[@]}")
    else
      saved_selection=("${selected[@]}")
      for ((i = 0; i < ${#service_names[@]}; i++)); do selected[i]=0; done
      selected[stop_all]=1
    fi
  elif stopping_all; then
    menu_message='Odznaci "Ugasi sve servise" da bi birao servise.'
  else
    menu_toggle_default "$1" "${#service_names[@]}"
  fi
}

menu_row_note() {
  local i=$1 dep j missing='' note=''
  if (( i == stop_all )); then
    REPLY="${c_dim}gasi i obavezne servise$c_reset"
    return
  fi
  if (( menu_locked[i] )) && ! stopping_all; then note="${c_dim}uvek radi$c_reset"; fi
  if (( selected[i] )) && ! is_active "${states[i]}"; then
    note+="${note:+  }$c_green$sym_start pokrenuce se$c_reset"
  elif (( ! selected[i] )) && is_active "${states[i]}"; then
    note+="${note:+  }$c_red$sym_stop zaustavice se$c_reset"
  fi
  if (( selected[i] )); then
    for dep in ${deps_of[${service_names[i]}]:-}; do
      j=${index_of[$dep]:-}
      if [[ -n $j ]] && (( ! selected[j] )); then missing+="${missing:+, }$dep"; fi
    done
    if [[ -n $missing ]]; then note+="${note:+  }$c_yellow$sym_warn zavisi i od: $missing$c_reset"; fi
  fi
  REPLY=$note
}

menu_footer() {
  local i start=0 stop=0
  for ((i = 0; i < ${#service_names[@]}; i++)); do
    if (( selected[i] )) && ! is_active "${states[i]}"; then start=$(( start + 1 )); fi
    if (( ! selected[i] )) && is_active "${states[i]}"; then stop=$(( stop + 1 )); fi
  done
  if stopping_all; then
    REPLY="${c_red}Enter gasi sve servise iz $compose_file (pokrenutih: $stop).$c_reset"
  elif (( start + stop == 0 )); then
    REPLY="${c_dim}Bez pokretanja i zaustavljanja.$c_reset"
  else
    REPLY="${c_green}Pokrece se: $start$c_reset $sym_sep ${c_red}Zaustavlja se: $stop$c_reset"
  fi
}

print_services() {
  local i
  printf 'Servisi iz %s:\n' "$compose_file"
  for ((i = 0; i < ${#service_names[@]}; i++)); do
    service_line "$i"
    printf '%2d. %s\n' "$(( i + 1 ))" "$REPLY"
  done
}

print_status() {
  local i
  printf '\n%sStanje servisa%s\n' "$c_bold" "$c_reset"
  for ((i = 0; i < ${#service_names[@]}; i++)); do
    service_line "$i"
    printf '  %s\n' "$REPLY"
  done
}

prepare_local_domains() {
  bash scripts/hosts.sh || printf '%sUpozorenje:%s hosts fajl nije azuriran; lokalni domeni mozda nece raditi.\n' "$c_yellow" "$c_reset"
  if tls_outdated; then
    printf 'HTTPS sertifikat nedostaje ili ne pokriva sve domene; pokrecem task tls.\n'
    bash scripts/tls.sh || printf '%sUpozorenje:%s HTTPS nije podesen; pokreni task tls.\n' "$c_yellow" "$c_reset"
  fi
}

apply_selection() {
  local i
  local -a up=() start=() stop=()
  if stopping_all; then
    printf '\n%sGasim sve servise iz %s%s\n' "$c_bold" "$compose_file" "$c_reset"
    docker compose stop
    load_states
    print_status
    return
  fi
  for ((i = 0; i < ${#service_names[@]}; i++)); do
    if (( selected[i] )); then
      up+=("${service_names[i]}")
      is_active "${states[i]}" || start+=("${service_names[i]}")
    elif (( exact )) && is_active "${states[i]}"; then
      stop+=("${service_names[i]}")
    fi
  done
  if (( ${#up[@]} == 0 && ${#stop[@]} == 0 )); then
    printf 'Nijedan servis nije odabran; nista nije promenjeno.\n'
    return
  fi
  printf '\n'
  if (( ${#stop[@]} > 0 )); then
    printf '%sZaustavljam:%s %s\n' "$c_bold" "$c_reset" "${stop[*]}"
    docker compose stop "${stop[@]}"
  fi
  if (( ${#start[@]} > 0 )); then
    printf '%sPokrecem:%s %s\n' "$c_bold" "$c_reset" "${start[*]}"
  elif (( ${#up[@]} > 0 )); then
    printf 'Odabrani servisi vec rade; primenjujem eventualne izmene konfiguracije.\n'
  fi
  if contains k-local "${up[@]}"; then prepare_local_domains; fi
  if (( ${#up[@]} > 0 )); then
    if (( exact )); then
      docker compose up -d --no-deps "${up[@]}"
    else
      docker compose up -d "${up[@]}"
    fi
  fi
  load_states
  print_status
}

services() {
  local i
  load_services
  if (( $# > 0 )); then
    for ((i = 0; i < ${#service_names[@]}; i++)); do selected[i]=${menu_locked[i]}; done
    exact=0
    menu_select_from_args "$@" || exit 1
  elif [[ -t 0 && -t 1 ]]; then
    add_stop_all_row
    menu_select_interactive 'Servisi koji treba da rade' 'Posle Enter rade tacno oznaceni; odznaceni koji rade se zaustavljaju, a zavisnosti se ne pokrecu same.' || { printf 'Odustali ste; nista nije promenjeno.\n'; exit 0; }
  else
    print_services
    fail 'Terminal nije interaktivan. Navedite servise za podizanje: task services -- k-fakture k-gateway, task services -- 1 3, ili task services -- all.'
  fi
  apply_selection
}

services "$@"
