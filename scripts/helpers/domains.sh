# Lokalni domeni k-docker-a: svi server_name iz nginx konfiguracije k-local-a.
# Iz njih se pune hosts fajlovi (scripts/hosts.sh) i HTTPS sertifikat
# (scripts/tls.sh). Skripta ga ucitava sa ". scripts/helpers/domains.sh".

tls_dir=containers/k-local/tls

local_domains() {
  awk '$1 == "server_name" { for (i = 2; i <= NF; i++) { d = $i; sub(/;$/, "", d); if (d != "" && d != "_") print d } }' \
    containers/k-local/conf.d/*.conf | sort -u
}

# tls_outdated: 0 kad sertifikat ili CA za kontejnere nedostaju ili sertifikat ne pokriva sve domene
tls_outdated() {
  local sans d
  [[ -f $tls_dir/local.pem && -f $tls_dir/rootCA.crt && -f $tls_dir/listen-443.conf ]] || return 0
  command -v openssl >/dev/null 2>&1 || return 1
  sans=$(openssl x509 -in "$tls_dir/local.pem" -noout -ext subjectAltName 2>/dev/null | tr -d ' \n'),
  while IFS= read -r d; do
    [[ $sans == *"DNS:$d,"* ]] || return 0
  done < <(local_domains)
  return 1
}
