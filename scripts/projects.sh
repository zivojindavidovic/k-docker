#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
. scripts/helpers/menu.sh

projects_file=scripts/helpers/projects.list
required_projects=(k-auth k-gateway)
env_files=(.env .env.example)

project_names=()
project_urls=()
project_hosts=()
project_dirs=()
project_paths=()
project_states=()
clone_urls=()
clone_errors=()
protocol=ssh
protocol_row=-1
menu_names=()
menu_lines=()
menu_locked=()
menu_divider=()
selected=()
name_width=0
host_width=0
dir_width=0
clone_log=''
clone_attempted=0
clone_succeeded=0

if (( menu_utf8 )); then
  sym_lamp_on='●' sym_lamp_off='○' sym_clone='↓' sym_ok='✔' sym_fail='✘'
else
  sym_lamp_on='*' sym_lamp_off='-' sym_clone='+' sym_ok='+' sym_fail='x'
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

# project_dir IME: putanja iz K_<IME>_PATH (.env, pa .env.example), inace ../IME
project_dir() {
  local var=${1#k-} file value=''
  var=K_${var^^}_PATH
  var=${var//[-.]/_}
  for file in "${env_files[@]}"; do
    [[ -f $file ]] || continue
    value=$(awk -v k="$var" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { print v }' "$file")
    value=${value%$'\r'}
    value=${value%%[[:space:]]#*}
    value=${value#[\"\']}
    value=${value%[\"\']}
    [[ -z $value ]] || break
  done
  REPLY=${value:-../$1}
}

project_state() {
  if [[ -e $1/.git ]]; then
    REPLY=cloned
  elif [[ -e $1 && ( ! -d $1 || -n $(ls -A -- "$1" 2>/dev/null) ) ]]; then
    REPLY=occupied
  else
    REPLY=missing
  fi
}

load_projects() {
  local line name url host extra i
  [[ -f $projects_file ]] || fail "Nedostaje $projects_file."
  while IFS= read -r line || [[ -n $line ]]; do
    read -r name url host extra <<< "${line%$'\r'}"
    [[ -n $name && $name != \#* ]] || continue
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && -n $url && -z $extra ]] || fail "Neispravan red u $projects_file: '$line'. Ocekuje se: ime URL [domen]"
    [[ -z $host || $host =~ ^[A-Za-z0-9.-]+$ ]] || fail "Neispravan domen u $projects_file: '$host'"
    project_names+=("$name")
    project_urls+=("$url")
    project_hosts+=("$host")
  done < "$projects_file"
  (( ${#project_names[@]} > 0 )) || fail "$projects_file je prazan."
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    project_dir "${project_names[i]}"
    project_dirs[i]=$REPLY
    project_paths[i]=$(realpath -m -- "$REPLY")
    project_state "${project_paths[i]}"
    project_states[i]=$REPLY
    clone_errors[i]=''
    menu_locked[i]=0
    selected[i]=0
    if [[ ${project_states[i]} != missing ]]; then
      menu_locked[i]=1
    elif contains "${project_names[i]}" "${required_projects[@]}"; then
      menu_locked[i]=1
      selected[i]=1
    fi
    if (( ${#project_names[i]} > name_width )); then name_width=${#project_names[i]}; fi
    if (( ${#project_hosts[i]} > host_width )); then host_width=${#project_hosts[i]}; fi
    if (( ${#project_dirs[i]} > dir_width )); then dir_width=${#project_dirs[i]}; fi
  done
  menu_names=("${project_names[@]}")
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    project_line "$i"
    menu_lines[i]=$REPLY
  done
}

status_text() {
  case $1 in
    cloned) printf -v REPLY '%s%s %-14s%s' "$c_green" "$sym_lamp_on" 'klonirano' "$c_reset" ;;
    occupied) printf -v REPLY '%s%s %-14s%s' "$c_yellow" "$sym_lamp_on" 'nije git repo' "$c_reset" ;;
    *) printf -v REPLY '%s%s %-14s%s' "$c_dim" "$sym_lamp_off" 'nije klonirano' "$c_reset" ;;
  esac
}

project_line() {
  local i=$1
  status_text "${project_states[i]}"
  printf -v REPLY '%-*s  %s  %-*s  %s%-*s%s' "$name_width" "${project_names[i]}" "$REPLY" "$host_width" "${project_hosts[i]}" "$c_dim" "$dir_width" "${project_dirs[i]}" "$c_reset"
}

# clone_url URL: adresa za izabrani protokol (git@host:putanja <-> https://host/putanja), u REPLY
clone_url() {
  REPLY=$1
  if [[ $protocol == https && $1 =~ ^git@([^:]+):(.+)$ ]]; then
    REPLY=https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}
  elif [[ $protocol == ssh && $1 =~ ^https://([^/@]+)/(.+)$ ]]; then
    REPLY=git@${BASH_REMATCH[1]}:${BASH_REMATCH[2]}
  fi
}

add_protocol_row() {
  protocol_row=${#project_names[@]}
  menu_names[protocol_row]='Kloniraj preko HTTPS-a'
  menu_lines[protocol_row]='Kloniraj preko HTTPS-a'
  menu_divider[protocol_row]=1
  selected[protocol_row]=0
  if [[ $protocol == https ]]; then selected[protocol_row]=1; fi
}

menu_toggle() {
  local i=$1
  if [[ $i == all ]]; then
    menu_toggle_default all "${#project_names[@]}"
  elif (( i == protocol_row )); then
    menu_toggle_default "$i"
    protocol=ssh
    if (( selected[i] )); then protocol=https; fi
  elif [[ ${project_states[i]} == cloned ]]; then
    menu_message="${project_names[i]} je vec kloniran u ${project_dirs[i]}."
  elif [[ ${project_states[i]} == occupied ]]; then
    menu_message="${project_dirs[i]} postoji, ali nije git repozitorijum; kloniranje nije moguce."
  elif (( menu_locked[i] )); then
    menu_message="${project_names[i]} je obavezan za rad sistema."
  else
    menu_toggle_default "$i"
  fi
}

menu_row_note() {
  local i=$1 note=''
  if (( i == protocol_row )); then
    if [[ $protocol == https ]]; then
      REPLY="${c_dim}privatni repozitorijumi traze GitHub korisnicko ime i Personal Access Token$c_reset"
    else
      REPLY="${c_dim}inace SSH; treba SSH kljuc dodat na GitHub nalog$c_reset"
    fi
    return
  fi
  if contains "${project_names[i]}" "${required_projects[@]}"; then note="${c_dim}obavezan$c_reset"; fi
  if (( selected[i] )) && [[ ${project_states[i]} == missing ]]; then
    note+="${note:+  }$c_green$sym_clone klonirace se$c_reset"
  fi
  REPLY=$note
}

menu_footer() {
  local i count=0 missing=0
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    [[ ${project_states[i]} == missing ]] || continue
    missing=$(( missing + 1 ))
    if (( selected[i] )); then count=$(( count + 1 )); fi
  done
  if (( missing == 0 )); then
    REPLY="${c_dim}Svi projekti su vec klonirani.$c_reset"
  elif (( count == 0 )); then
    REPLY="${c_dim}Nista nije odabrano za kloniranje.$c_reset"
  else
    REPLY="${c_green}Klonira se: $count$c_reset $sym_sep preko ${protocol^^}-a"
  fi
}

print_projects() {
  local i line
  printf 'Projekti iz %s:\n' "$projects_file"
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    project_line "$i"
    line=$REPLY
    clone_url "${project_urls[i]}"
    printf '%2d. %s  %s\n' "$(( i + 1 ))" "$line" "$REPLY"
  done
}

# clone_reason: razlog neuspelog git clone iz $clone_log, u REPLY
clone_reason() {
  local log
  log=$(tr '\r' '\n' < "$clone_log")
  case $log in
    *'Permission denied (publickey)'*)
      REPLY='SSH pristup odbijen: SSH kljuc nije dodat na GitHub nalog ili nalog nema pristup repozitorijumu; ili kloniraj preko HTTPS-a.' ;;
    *'Host key verification failed'*)
      REPLY='SSH: github.com nije potvrdjen kao poznat host; pokreni ssh -T git@github.com i potvrdi sa yes.' ;;
    *'Repository not found'* | *"fatal: repository '"*"' not found"*)
      REPLY='Repozitorijum nije pronadjen ili tvoj nalog nema pristup (GitHub isto javlja za privatni repozitorijum bez pristupa).' ;;
    *'Permission to '*' denied'* | *'returned error: 403'*)
      REPLY='Pristup odbijen (403): nalog nema dozvolu za ovaj repozitorijum.' ;;
    *'Authentication failed'* | *'Invalid username or password'*)
      REPLY='Prijava nije uspela: za HTTPS se umesto lozinke unosi Personal Access Token; ili kloniraj preko SSH-a.' ;;
    *'could not read Username'* | *'terminal prompts disabled'*)
      REPLY='Repozitorijum trazi prijavu, a korisnicko ime i token nisu uneti.' ;;
    *'Could not resolve host'* | *'Could not resolve hostname'*)
      REPLY='Nema mreze ili DNS ne radi (host nije pronadjen).' ;;
    *)
      REPLY=$(grep -E '^(fatal|error|ERROR):' <<< "$log" | tail -n 1 || true)
      REPLY=${REPLY:-git clone nije uspeo; pogledaj izlaz iznad.} ;;
  esac
}

clone_selected() {
  local i name
  local -a todo=()
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    (( selected[i] )) || continue
    if [[ ${project_states[i]} == missing ]]; then
      todo+=("$i")
    else
      printf '%s: vec postoji u %s, preskacem.\n' "${project_names[i]}" "${project_dirs[i]}"
    fi
  done
  if (( ${#todo[@]} == 0 )); then
    printf 'Nema projekata za kloniranje.\n'
    return
  fi
  clone_log=$(mktemp)
  trap 'rm -f -- "$clone_log"' EXIT
  for i in "${todo[@]}"; do
    name=${project_names[i]}
    clone_url "${project_urls[i]}"
    clone_urls[i]=$REPLY
    printf '\n%sKloniram %s%s iz %s u %s\n' "$c_bold" "$name" "$c_reset" "${clone_urls[i]}" "${project_dirs[i]}"
    clone_attempted=$(( clone_attempted + 1 ))
    if git clone --progress -- "${clone_urls[i]}" "${project_paths[i]}" 2>&1 | tee "$clone_log"; then
      project_states[i]=cloned
      clone_succeeded=$(( clone_succeeded + 1 ))
    else
      clone_reason
      clone_errors[i]=$REPLY
    fi
  done
}

print_summary() {
  local i color=$c_green mark=$sym_ok
  (( clone_attempted > 0 )) || return 0
  if (( clone_succeeded == 0 )); then
    color=$c_red mark=$sym_fail
  elif (( clone_succeeded < clone_attempted )); then
    color=$c_yellow
  fi
  printf '\n%sRezultat kloniranja%s\n' "$c_bold" "$c_reset"
  printf '  %s%s Uspesno klonirano: %d od %d%s\n' "$color" "$mark" "$clone_succeeded" "$clone_attempted" "$c_reset"
  (( clone_succeeded < clone_attempted )) || return 0
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    [[ -n ${clone_errors[i]} ]] || continue
    printf '  %s%s %s%s  %s%s%s\n' "$c_red" "$sym_fail" "${project_names[i]}" "$c_reset" "$c_dim" "${clone_urls[i]}" "$c_reset"
    printf '    %s\n' "${clone_errors[i]}"
  done
  return 1
}

projects() {
  local status=0 arg
  local -a args=()
  for arg; do
    case $arg in
      --ssh) protocol=ssh ;;
      --https) protocol=https ;;
      *) args+=("$arg") ;;
    esac
  done
  command -v git >/dev/null 2>&1 || fail 'Git nije instaliran ili nije na PATH-u.'
  load_projects
  if (( ${#args[@]} > 0 )); then
    menu_select_from_args "${args[@]}" || exit 1
  elif [[ -t 0 && -t 1 ]]; then
    add_protocol_row
    menu_select_interactive 'Projekti' "Klonirani projekti se ne biraju ponovo; novi se kloniraju u putanju iz .env (K_<IME>_PATH), pored k-docker." || { printf 'Odustali ste; nista nije klonirano.\n'; exit 0; }
  else
    print_projects
    fail 'Terminal nije interaktivan. Navedite projekte: task projects -- k-fakture, task projects -- 1 3, ili task projects -- all (dodajte --https za HTTPS umesto SSH-a).'
  fi
  clone_selected
  printf '\n'
  bash scripts/hosts.sh || status=1
  print_summary || status=1
  exit "$status"
}

projects "$@"
