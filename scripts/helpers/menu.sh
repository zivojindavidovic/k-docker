# Zajednicki interaktivni meni za skripte u scripts/. Ulaz: menu_lines (tekst
# stavki), menu_names (nazivi za izbor argumentom), selected (0/1 po stavci) i
# opciono menu_locked (1 = stavka ne moze da se iskljuci) i menu_divider (1 =
# linija iznad stavke); izlaz: selected. Ako skripta definise menu_row_note
# I ili menu_footer, meni ih poziva pri svakom crtanju i ispisuje REPLY; ako
# definise menu_toggle, razmak i a pozivaju nju umesto menu_toggle_default.
# Skripta ga ucitava sa ". scripts/helpers/menu.sh".

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  c_reset=$'\e[0m' c_bold=$'\e[1m' c_dim=$'\e[2m' c_red=$'\e[31m' c_green=$'\e[32m' c_yellow=$'\e[33m' c_cyan=$'\e[36m'
else
  c_reset='' c_bold='' c_dim='' c_red='' c_green='' c_yellow='' c_cyan=''
fi

if [[ $(locale charmap 2>/dev/null) == UTF-8 ]]; then
  menu_utf8=1 sym_on='■' sym_off='□' sym_pointer='❯' sym_sep='·' sym_updown='↑/↓' sym_rule='─'
else
  menu_utf8=0 sym_on='[x]' sym_off='[ ]' sym_pointer='>' sym_sep='|' sym_updown='strelice' sym_rule='-'
fi
printf -v menu_rule '%*s' 32 ''
menu_rule=${menu_rule// /$sym_rule}

menu_drawn=0
menu_message=''

restore_terminal() {
  stty echo 2>/dev/null || true
  printf '\e[?7h\e[?25h'
}

# menu_draw KURSOR: crta stavke na mestu prethodnog crtanja; KURSOR -1 je zavrsni prikaz
menu_draw() {
  local cursor=$1 count=${#menu_lines[@]} i pointer box text frame='' lines=0
  if (( menu_drawn > 0 )); then printf -v frame '\r\e[%dA' "$menu_drawn"; fi
  for ((i = 0; i < count; i++)); do
    if (( ${menu_divider[i]:-0} )); then
      frame+=$'\e[2K'"      $c_dim$menu_rule$c_reset"$'\n'
      lines=$(( lines + 1 ))
    fi
    pointer=' '
    text=${menu_lines[i]}
    if (( i == cursor )); then
      pointer=$c_cyan$sym_pointer$c_reset
      text=$c_bold$text$c_reset
    fi
    box=$sym_off
    if (( selected[i] )); then box=$sym_on; fi
    if (( selected[i] && ! ${menu_locked[i]:-0} )); then
      box=$c_green$box$c_reset
    else
      box=$c_dim$box$c_reset
    fi
    REPLY=''
    if declare -F menu_row_note >/dev/null; then menu_row_note "$i"; fi
    frame+=$'\e[2K'" $pointer $box  $text${REPLY:+  $REPLY}"$'\n'
    lines=$(( lines + 1 ))
  done
  if (( cursor >= 0 )); then
    frame+=$'\e[2K\n'
    lines=$(( lines + 1 ))
    if declare -F menu_footer >/dev/null; then
      menu_footer
      frame+=$'\e[2K'"   $REPLY"$'\n'
      lines=$(( lines + 1 ))
    fi
    frame+=$'\e[2K'"   $c_dim$sym_updown kretanje $sym_sep razmak oznaci $sym_sep a sve $sym_sep Enter potvrdi $sym_sep q odustani$c_reset"$'\n'
    lines=$(( lines + 1 ))
    if [[ -n $menu_message ]]; then
      frame+=$'\e[2K'"   $c_yellow$menu_message$c_reset"$'\n'
      lines=$(( lines + 1 ))
    fi
  fi
  printf '%s\e[J' "$frame"
  menu_drawn=$lines
}

# menu_toggle_default STAVKA|all [BROJ]: menja oznaku stavke; all oznacava ili odznacava prvih BROJ stavki
menu_toggle_default() {
  local count=${2:-${#menu_lines[@]}} i all=1
  if [[ $1 != all ]]; then
    if (( ${menu_locked[$1]:-0} )); then
      menu_message="${menu_names[$1]:-Ova stavka} ne moze da se iskljuci."
    else
      selected[$1]=$(( 1 - selected[$1] ))
    fi
    return
  fi
  for ((i = 0; i < count; i++)); do (( ${menu_locked[i]:-0} || selected[i] )) || { all=0; break; }; done
  for ((i = 0; i < count; i++)); do
    (( ${menu_locked[i]:-0} )) || selected[i]=$(( 1 - all ))
  done
}

# menu_select_interactive NASLOV [OPIS] -> 0 kad se izbor potvrdi, 1 kad se odustane
menu_select_interactive() {
  local title=$1 description=${2:-} count=${#menu_lines[@]} cursor=0 key seq toggle=menu_toggle_default
  printf '%s%s%s\n' "$c_bold" "$title" "$c_reset"
  if [[ -n $description ]]; then printf '%s%s%s\n' "$c_dim" "$description" "$c_reset"; fi
  printf '\n'
  if declare -F menu_toggle >/dev/null; then toggle=menu_toggle; fi
  trap restore_terminal EXIT
  trap 'restore_terminal; printf "\n"; exit 130' INT TERM
  stty -echo
  printf '\e[?25l\e[?7l'
  menu_drawn=0
  menu_message=''
  while :; do
    menu_draw "$cursor"
    menu_message=''
    IFS= read -rsn1 key || key=q
    case $key in
      $'\e')
        seq=''
        IFS= read -rsn2 -t 0.05 seq || true
        case $seq in
          '[A' | 'OA') cursor=$(( (cursor + count - 1) % count )) ;;
          '[B' | 'OB') cursor=$(( (cursor + 1) % count )) ;;
          '') key=q ;;
        esac
        ;;
      k | K) cursor=$(( (cursor + count - 1) % count )) ;;
      j | J) cursor=$(( (cursor + 1) % count )) ;;
      ' ') "$toggle" "$cursor" ;;
      a | A) "$toggle" all ;;
      '') break ;;
    esac
    if [[ $key == [qQ] ]]; then
      printf '\r\e[%dA\e[J' "$menu_drawn"
      restore_terminal
      trap - INT TERM
      return 1
    fi
  done
  menu_draw -1
  restore_terminal
  trap - INT TERM
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
