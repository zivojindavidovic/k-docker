# Zajednicki interaktivni meni za skripte u scripts/. Ulaz: menu_lines (tekst
# stavki), menu_names (nazivi za izbor argumentom) i selected (0/1 po stavci);
# izlaz: selected. Skripta ga ucitava sa ". scripts/helpers/menu.sh".

restore_terminal() {
  stty echo 2>/dev/null || true
  printf '\e[?25h'
}

# menu_select_interactive NASLOV -> 0 kad se izbor potvrdi, 1 kad se odustane
menu_select_interactive() {
  local title=$1 count=${#menu_lines[@]} cursor=0 i key seq cols pointer mark line all
  read -r _ cols < <(stty size 2>/dev/null) || cols=''
  [[ $cols =~ ^[0-9]+$ && $cols -gt 20 ]] || cols=80
  printf '%s\n' "$title"
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
      line="$pointer [$mark] ${menu_lines[i]}"
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
        trap - INT TERM
        printf '\n'
        return 1
        ;;
    esac
  done
  restore_terminal
  trap - INT TERM
  printf '\n'
}

# menu_select_from_args ARG... : redni brojevi, nazivi iz menu_names ili all
menu_select_from_args() {
  local count=${#menu_lines[@]} joined="$*" arg i found
  local -a args
  IFS=', ' read -ra args <<< "$joined"
  for arg in "${args[@]}"; do
    [[ -n $arg ]] || continue
    if [[ $arg == all ]]; then
      for ((i = 0; i < count; i++)); do selected[i]=1; done
      continue
    fi
    if [[ $arg =~ ^[0-9]+$ ]] && (( 10#$arg >= 1 && 10#$arg <= count )); then
      selected[$(( 10#$arg - 1 ))]=1
      continue
    fi
    found=0
    for ((i = 0; i < count; i++)); do
      if [[ ${menu_names[i]:-} == "$arg" ]]; then selected[i]=1; found=1; break; fi
    done
    if (( ! found )); then
      printf "Greska: nepoznat izbor '%s'. Navedite brojeve 1-%d ili nazive razdvojene razmakom, ili all.\n" "$arg" "$count" >&2
      return 1
    fi
  done
}
