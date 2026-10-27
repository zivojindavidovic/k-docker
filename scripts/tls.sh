#!/usr/bin/env bash
# Lokalni HTTPS za *.local domene (nginx k-local, port 443) — Linux i Windows (WSL2).
#
#   task tls
#
# 1. mkcert: koristi postojeci ili ga preuzima u ~/.local/bin (bez sudo).
# 2. Linux: libnss3-tools (certutil), da Chrome/Firefox veruju CA-u.
# 3. Lokalni razvojni CA (mkcert -install, jednom po racunaru).
# 4. WSL: isti CA i u Windows skladiste korisnika (Chrome/Edge na Windows-u).
# 5. Sertifikat za sve server_name domene iz containers/k-local/conf.d, nginx
#    snippet containers/k-local/tls/listen-443.conf (443 + preusmerenje sa HTTP-a)
#    i kopija CA-a (tls/rootCA.crt) kojoj veruje k-gateway; pa reload k-local.
#
# Bez ovog koraka nginx radi samo na portu 80 (snippet ne postoji). task services
# ga pokrece sam kad sertifikat nedostaje ili ne pokriva sve domene.
# Bezbedno je pokretati vise puta (npr. posle dodavanja novog vhost-a).
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
. scripts/helpers/domains.sh

local_bin=$HOME/.local/bin

fail() {
  printf 'Greska: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Upozorenje: %s\n' "$*" >&2
}

is_wsl() {
  [[ -n ${WSL_DISTRO_NAME:-} ]] || grep -qi microsoft /proc/version 2>/dev/null
}

ensure_mkcert() {
  command -v mkcert >/dev/null 2>&1 && return

  if [[ -x $local_bin/mkcert ]]; then
    PATH=$local_bin:$PATH
    return
  fi

  local arch
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) fail "nepodrzana arhitektura $(uname -m); instaliraj mkcert rucno: sudo apt install -y mkcert" ;;
  esac

  printf 'mkcert nije instaliran; preuzimam ga u %s ...\n' "$local_bin"
  mkdir -p "$local_bin"
  curl -fsSL -o "$local_bin/mkcert" "https://dl.filippo.io/mkcert/latest?for=linux/$arch" \
    || fail 'preuzimanje mkcert-a nije uspelo; instaliraj ga rucno: sudo apt install -y mkcert'
  chmod +x "$local_bin/mkcert"
  PATH=$local_bin:$PATH
}

# Chrome i Firefox na Linuxu imaju svoje skladiste (NSS); mkcert u njega upisuje
# CA samo ako postoji certutil. Na WSL-u browser je na Windows-u, pa ne treba.
ensure_nss_tools() {
  command -v certutil >/dev/null 2>&1 && return

  if command -v apt-get >/dev/null 2>&1; then
    printf 'Instaliram libnss3-tools (certutil) za Chrome/Firefox (sudo)...\n'
    sudo apt-get install -y libnss3-tools >/dev/null && return
  fi

  warn 'nema certutil-a (paket libnss3-tools); Chrome/Firefox na Linuxu nece verovati sertifikatu dok ga ne instaliras i ponovis task tls.'
}

# Uvoz CA u Windows skladiste trenutnog korisnika (Cert:\CurrentUser\Root).
# Ne trazi administratora; Windows jednom pita za potvrdu (prozor "Security Warning").
# Preskace se ako je CA vec uvezen.
install_ca_windows() {
  local ca thumbprint win_temp win_ca

  if ! command -v powershell.exe >/dev/null 2>&1; then
    warn 'powershell.exe nije dostupan iz WSL-a (interop iskljucen?); CA uvezi rucno (README, odeljak HTTPS).'
    return 1
  fi

  ca="$(mkcert -CAROOT)/rootCA.pem"
  thumbprint=$(openssl x509 -in "$ca" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')

  if powershell.exe -NoProfile -Command \
    "if (Get-ChildItem Cert:\\CurrentUser\\Root | Where-Object Thumbprint -eq '$thumbprint') { exit 0 } else { exit 1 }" \
    >/dev/null 2>&1; then
    printf 'Windows: lokalni CA je vec uvezen.\n'
    return 0
  fi

  win_temp=$(powershell.exe -NoProfile -Command '[IO.Path]::GetTempPath()' | tr -d '\r')
  win_ca="${win_temp}k-docker-rootCA.pem"
  cp "$ca" "$(wslpath -u "$win_ca")"

  printf 'Windows: uvozim lokalni CA; potvrdi prozor "Security Warning" na Windows-u (Yes)...\n'
  if ! powershell.exe -NoProfile -Command \
    "\$ErrorActionPreference = 'Stop'; try { Import-Certificate -FilePath '$win_ca' -CertStoreLocation Cert:\\CurrentUser\\Root | Out-Null } finally { Remove-Item -ErrorAction SilentlyContinue '$win_ca' }" \
    >/dev/null; then
    warn 'uvoz CA u Windows nije uspeo (ili je odbijen); ponovi task tls ili ga uvezi rucno (README, odeljak HTTPS).'
    return 1
  fi

  printf 'Windows: lokalni CA je uvezen (vazi za Chrome i Edge; restartuj browser).\n'
}

ensure_mkcert

mapfile -t domains < <(local_domains)
(( ${#domains[@]} > 0 )) || fail 'nema server_name domena u containers/k-local/conf.d.'

is_wsl || ensure_nss_tools

printf 'Instaliram lokalni CA (mkcert -install; moze traziti sudo lozinku)...\n'
mkcert -install

if is_wsl; then
  install_ca_windows || true
fi

printf 'Pravim sertifikat za: %s\n' "${domains[*]}"
mkdir -p "$tls_dir"
mkcert -cert-file "$tls_dir/local.pem" -key-file "$tls_dir/local-key.pem" "${domains[@]}" >/dev/null 2>&1
cp "$(mkcert -CAROOT)/rootCA.pem" "$tls_dir/rootCA.crt"
chmod 644 "$tls_dir/local.pem" "$tls_dir/local-key.pem" "$tls_dir/rootCA.crt"

cat > "$tls_dir/listen-443.conf" <<'CONF'
# Generisao scripts/tls.sh — ne menjati rucno.
listen 443 ssl;
ssl_certificate     /etc/nginx/tls/local.pem;
ssl_certificate_key /etc/nginx/tls/local-key.pem;
if ($scheme = http) {
    return 301 https://$host$request_uri;
}
CONF

if [[ -n $(docker compose ps -q --status running k-local 2>/dev/null) ]]; then
  printf 'Ucitavam novi sertifikat u k-local...\n'
  docker compose exec -T k-local nginx -t >/dev/null 2>&1 || fail 'nginx konfiguracija nije ispravna (docker compose exec k-local nginx -t).'
  docker compose exec -T k-local nginx -s reload >/dev/null
fi

printf '\nGotovo. HTTPS radi za:\n'
printf '  https://%s\n' "${domains[@]}"
