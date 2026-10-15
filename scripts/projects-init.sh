#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

projects_file=scripts/helpers/projects.list
projects_dir=$(cd .. && pwd)
linux_hosts=/etc/hosts
windows_hosts=/mnt/c/Windows/System32/drivers/etc/hosts

project_names=()
project_urls=()
project_hosts=()
project_notes=()
selected=()
name_width=0
host_width=0
note_width=0
clone_failed=0
hosts_failed=0

fail() {
  printf 'Greska: %s\n' "$*" >&2
  exit 1
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
    selected[i]=0
    project_notes[i]=''
    if [[ -e $projects_dir/${project_names[i]} ]]; then project_notes[i]='(vec klonirano)'; fi
    if (( ${#project_names[i]} > name_width )); then name_width=${#project_names[i]}; fi
    if (( ${#project_hosts[i]} > host_width )); then host_width=${#project_hosts[i]}; fi
    if (( ${#project_notes[i]} > note_width )); then note_width=${#project_notes[i]}; fi
  done
}

project_line() {
  local i=$1 line
  line=$(printf '%2d. %-*s' "$(( i + 1 ))" "$name_width" "${project_names[i]}")
  if (( note_width > 0 )); then line+=$(printf '  %-*s' "$note_width" "${project_notes[i]}"); fi
  if (( host_width > 0 )); then line+=$(printf '  %-*s' "$host_width" "${project_hosts[i]}"); fi
  printf '%s  %s' "$line" "${project_urls[i]}"
}

print_projects() {
  local i
  printf 'Dostupni projekti. Odrediste: %s\n' "$projects_dir"
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    project_line "$i"
    printf '\n'
  done
}

restore_terminal() {
  stty echo 2>/dev/null || true
  printf '\e[?25h'
}

select_interactive() {
  local count=${#project_names[@]} cursor=0 i key seq cols pointer mark line all
  read -r _ cols < <(stty size 2>/dev/null) || cols=''
  [[ $cols =~ ^[0-9]+$ && $cols -gt 20 ]] || cols=80
  printf 'Dostupni projekti. Odrediste: %s\n' "$projects_dir"
  printf 'Razmak: oznaci/ponisti, strelice ili j/k: kretanje, a: svi, Enter: potvrdi, q: odustani.\n\n'
  trap restore_terminal EXIT
  trap 'restore_terminal; printf "\n"; exit 130' INT TERM
  stty -echo
  printf '\e[?25l'
  for ((i = 0; i < count; i++)); do printf '\n'; done
  while :; do
    printf '\e[%dA' "$count"
    for ((i = 0; i < count; i++)); do
      pointer=' '
      mark=' '
      if (( i == cursor )); then pointer='>'; fi
      if (( selected[i] )); then mark='x'; fi
      line="$pointer [$mark] $(project_line "$i")"
      printf '\e[2K%s\n' "${line:0:cols-1}"
    done
    IFS= read -rsn1 key || key=q
    case $key in
      $'\e')
        IFS= read -rsn2 -t 0.05 seq || seq=''
        case $seq in
          '[A' | 'OA') cursor=$(( (cursor + count - 1) % count )) ;;
          '[B' | 'OB') cursor=$(( (cursor + 1) % count )) ;;
        esac
        ;;
      k | K) cursor=$(( (cursor + count - 1) % count )) ;;
      j | J) cursor=$(( (cursor + 1) % count )) ;;
      ' ') selected[cursor]=$(( 1 - selected[cursor] )) ;;
      a | A)
        all=1
        for ((i = 0; i < count; i++)); do (( selected[i] )) || { all=0; break; }; done
        for ((i = 0; i < count; i++)); do selected[i]=$(( 1 - all )); done
        ;;
      '') break ;;
      q | Q)
        restore_terminal
        printf '\nOdustali ste; nista nije klonirano.\n'
        exit 0
        ;;
    esac
  done
  restore_terminal
  trap - INT TERM
  printf '\n'
}

select_from_args() {
  local count=${#project_names[@]} joined="$*" arg i
  local -a args
  IFS=', ' read -ra args <<< "$joined"
  for arg in "${args[@]}"; do
    if [[ -z $arg ]]; then
      continue
    elif [[ $arg == all ]]; then
      for ((i = 0; i < count; i++)); do selected[i]=1; done
    elif [[ $arg =~ ^[0-9]+$ ]] && (( 10#$arg >= 1 && 10#$arg <= count )); then
      selected[$(( 10#$arg - 1 ))]=1
    else
      fail "Nepoznat izbor '$arg'. Navedite brojeve 1-$count razdvojene razmakom ili all."
    fi
  done
}

clone_selected() {
  local i name url dest cloned=0 skipped=0 any=0
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    (( selected[i] )) || continue
    any=1
    name=${project_names[i]}
    url=${project_urls[i]}
    dest=$projects_dir/$name
    if [[ -e $dest ]]; then
      printf '%s: %s vec postoji, preskacem.\n' "$name" "$dest"
      skipped=$(( skipped + 1 ))
      continue
    fi
    printf 'Kloniram %s iz %s u %s\n' "$name" "$url" "$dest"
    if git clone -- "$url" "$dest"; then
      cloned=$(( cloned + 1 ))
    else
      printf 'Greska: kloniranje %s nije uspelo.\n' "$name" >&2
      clone_failed=$(( clone_failed + 1 ))
    fi
  done
  if (( any == 0 )); then
    printf 'Nijedan projekat nije odabran; nista nije klonirano.\n'
    return
  fi
  printf 'Klonirano: %d, preskoceno: %d, neuspesno: %d.\n' "$cloned" "$skipped" "$clone_failed"
}

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
    printf '%s: unosi vec postoje.\n' "$file"
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
    printf 'Windows hosts: unosi vec postoje.\n'
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

configure_hosts() {
  local i hosts=() h
  for ((i = 0; i < ${#project_names[@]}; i++)); do
    if (( selected[i] )) && [[ -n ${project_hosts[i]} ]]; then hosts+=("${project_hosts[i]}"); fi
  done
  (( ${#hosts[@]} > 0 )) || return 0
  printf '\nLokalni domeni odabranih projekata: %s\n' "${hosts[*]}"
  add_hosts_linux "${hosts[@]}" || hosts_failed=1
  if is_wsl; then
    add_hosts_windows "${hosts[@]}" || hosts_failed=1
  fi
  if (( hosts_failed )); then
    printf 'Dodajte rucno u /etc/hosts (Linux/WSL) i u C:\\Windows\\System32\\drivers\\etc\\hosts (Windows, kao administrator):\n' >&2
    for h in "${hosts[@]}"; do printf '  127.0.0.1 %s\n' "$h" >&2; done
  fi
}

projects_init() {
  command -v git >/dev/null 2>&1 || fail 'Git nije instaliran ili nije na PATH-u.'
  load_projects
  if (( $# > 0 )); then
    select_from_args "$@"
  elif [[ -t 0 && -t 1 ]]; then
    select_interactive
  else
    print_projects
    fail 'Terminal nije interaktivan. Navedite brojeve: task projects-init -- 1 2, ili task projects-init -- all.'
  fi
  clone_selected
  configure_hosts
  (( clone_failed == 0 )) || fail "Neki projekti nisu klonirani. Proverite URL u $projects_file, mrezu i GitHub pristup; za privatne repozitorijume koristite Personal Access Token umesto lozinke."
  (( hosts_failed == 0 )) || fail 'Hosts fajl nije azuriran u potpunosti; pogledajte poruke iznad.'
}

projects_init "$@"
