#!/usr/bin/env bash
# Puni lokalne MariaDB baze za auth:
#   k-master-db    <- office-master-init.sql            + scripts/seed/master-local.sql
#   k-license-1-db <- office-licence-init-*.sql (office_licenca)  + scripts/seed/tenant-local.sql
#   k-license-2-db <- office-licence-init-*.sql (office_licenca3) + scripts/seed/tenant-local.sql
#   k-license-2-db <- office-licence-init-*.sql (office_licenca4): prazna baza slobodne licence 4
#                     (proba registracije); pravi se ispocetka pri svakom pokretanju
#
# Dump-ovi nisu u repou; direktorijum je K_DB_DUMPS_PATH iz .env
# (podrazumevano ../rokovnik/docker/db).
#
#   task db-init               # samo prazne baze (bezbedno)
#   task db-init -- --force    # brise i ponovo pravi office_master i obe licence
#   task db-init -- --local    # samo test korisnici/licence (seed/*.sql), bez dump-ova
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

fail() {
  printf 'Greska: %s\n' "$*" >&2
  exit 1
}

env_value() {
  [[ -f .env ]] || return 0
  sed -n "s/^$1=//p" .env | tail -n 1
}

force=0
local_only=0
for arg in "$@"; do
  case $arg in
    --force) force=1 ;;
    --local) local_only=1 ;;
    *) fail "Nepoznat argument '$arg'. Dozvoljeno: --force, --local" ;;
  esac
done

dumps=$(env_value K_DB_DUMPS_PATH)
dumps=${dumps:-../rokovnik/docker/db}
master_dump=$dumps/office-master-init.sql
license_dump=$(ls -1 "$dumps"/office-licence-init-*.sql 2>/dev/null | sort | tail -n 1 || true)

# servis | baza | ID licence u office_license | naziv firme
tenants=(
  "k-license-1-db|office_licenca|1|Paragraf Licenca 1"
  "k-license-2-db|office_licenca3|3|Paragraf Licenca 3"
)

# Dump-ovi su iz MySQL 5.7; MariaDB 12 odbija nekoliko konstrukcija koje 5.7
# toleriše. Ispravke se rade u letu, dump fajl se ne menja:
#  - `BIGINT UNSIGNED UNSIGNED` -> `BIGINT UNSIGNED`
#  - neimenovani FK u MariaDB-u se zovu `1`, `2`... (MySQL: <tabela>_ibfk_N);
#    menja se samo za tkt_* tabele, ostali *_ibfk_N u dump-u su eksplicitno imenovani
#  - MariaDB ne skida kolonu iz slozenog UNIQUE indeksa sam (tkt_channel_user)
mysql57_compat() {
  sed -e 's/UNSIGNED UNSIGNED/UNSIGNED/g' \
      -e 's/^\(\s*\)DROP FOREIGN KEY tkt_channel_user_ibfk_1,/\1DROP INDEX user_id,\n\1DROP FOREIGN KEY tkt_channel_user_ibfk_1,/' \
      -e 's/DROP FOREIGN KEY tkt_[A-Za-z0-9_]*_ibfk_\([0-9][0-9]*\)/DROP FOREIGN KEY `\1`/g' \
      "$1"
}

sql() {
  local service=$1
  shift
  docker compose exec -T "$service" mariadb -uroot "$@"
}

table_count() {
  sql "$1" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$2'"
}

printf 'Podizem k-master-db, k-license-1-db, k-license-2-db...\n'
docker compose up -d --wait k-master-db k-license-1-db k-license-2-db >/dev/null

if (( ! local_only )); then
  [[ -f $master_dump ]] || fail "Nema $master_dump (K_DB_DUMPS_PATH u .env)."
  [[ -n $license_dump ]] || fail "Nema office-licence-init-*.sql u $dumps (K_DB_DUMPS_PATH u .env)."

  if (( $(table_count k-master-db office_master) > 0 )) && (( ! force )); then
    printf 'office_master vec ima tabele, preskacem uvoz (--force za ponovni uvoz).\n'
  else
    printf 'Uvozim office_master iz %s...\n' "$master_dump"
    sql k-master-db -e 'DROP DATABASE IF EXISTS `office_master`'
    mysql57_compat "$master_dump" | sql k-master-db
  fi

  for entry in "${tenants[@]}"; do
    IFS='|' read -r service db license company <<< "$entry"
    if (( $(table_count "$service" "$db") > 0 )) && (( ! force )); then
      printf '%s/%s vec ima tabele, preskacem uvoz (--force za ponovni uvoz).\n' "$service" "$db"
      continue
    fi
    printf 'Uvozim %s/%s iz %s...\n' "$service" "$db" "$license_dump"
    sql "$service" -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\` CHARACTER SET utf8 COLLATE utf8_general_ci"
    mysql57_compat "$license_dump" | sql "$service" "$db"
  done
fi

# Slobodna licenca 4 (registracija): uvek cista baza iz sablona.
if [[ -n $license_dump ]]; then
  printf 'Pravim praznu k-license-2-db/office_licenca4 iz %s (slobodna licenca 4)...\n' "$license_dump"
  sql k-license-2-db -e 'DROP DATABASE IF EXISTS `office_licenca4`; CREATE DATABASE `office_licenca4` CHARACTER SET utf8 COLLATE utf8_general_ci'
  mysql57_compat "$license_dump" | sql k-license-2-db office_licenca4
else
  printf 'Nema dump-a licence; preskacem praznu bazu za licencu 4 (registracija).\n'
fi

printf 'Primenjujem lokalne licence i test korisnike...\n'
sql k-master-db < scripts/seed/master-local.sql
for entry in "${tenants[@]}"; do
  IFS='|' read -r service db license company <<< "$entry"
  { printf "USE \`%s\`;\nSET @company = '%s';\nSET @license = %s;\n" "$db" "$company" "$license"
    cat scripts/seed/tenant-local.sql
  } | sql "$service"
done

printf '\nGotovo. Licence:\n'
sql k-master-db -t -e 'SELECT ID, appCode, RegistrationDate, DBHost, DataBaseName, login_2fa FROM office_master.office_license ORDER BY ID'
printf 'Test korisnici (lozinka: password):\n'
sql k-master-db -t -e "SELECT userName, GROUP_CONCAT(licenseID ORDER BY licenseID) AS licence FROM office_master.office_users WHERE userName LIKE 'developer-%@paragraf.rs' GROUP BY userName"
