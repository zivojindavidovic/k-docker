# k-docker

Lokalno razvojno okruženje za Kancelarko projekte. Jedan `docker compose`
drži zajedničke servise (nginx, PostgreSQL, Redis, MariaDB za office_master i
licence) i
kontejnere aplikacija. Projekti se kloniraju pored ovog repozitorijuma, a
domeni `*.local` vode na njih.

## Preduslovi

**Ubuntu:** Git, [Docker Engine](https://docs.docker.com/engine/install/ubuntu/)
sa Compose plugin-om i [Task](https://taskfile.dev/docs/installation).

**Windows:** [WSL2](https://learn.microsoft.com/windows/wsl/install) sa
Ubuntu-om, pa unutar WSL-a isto što i gore. Ako koristiš Docker Desktop
umesto Docker Engine-a u WSL-u, uključi *Settings → Resources → Network →
Enable host networking*. Sve komande kucaš u WSL terminalu, a repozitorijume
držiš u Linux fajl sistemu (`~/Kancelarko`), ne u `/mnt/c`.

Port 80 mora biti slobodan. Ako na mašini radi Apache:

```bash
sudo systemctl disable --now apache2
```

## Prvo pokretanje

```bash
git clone <url> ~/Kancelarko/k-docker   # direktorijum mora da se zove k-docker
cd ~/Kancelarko/k-docker
cp .env.example .env
task projects-init                      # izaberi projekte
task services                           # izaberi servise
```

`task projects-init` klonira izabrane projekte u `~/Kancelarko/<ime>` i
upisuje njihove domene u hosts fajl. Linux traži sudo lozinku; Windows pored
toga otvara UAC prozor koji treba potvrditi, inače domeni ne rade iz Windows
browsera. Privatni repozitorijumi traže GitHub korisničko ime i Personal
Access Token; `git config --global credential.helper store` ih pamti.

Bez menija:

```bash
task projects-init -- all     # svi projekti
task projects-init -- 1 3     # po rednom broju iz liste
```

Posle prvog `task services` pogledaj sekciju projekta ispod, jer neki traže
još koji korak.

## HTTPS (lokalno)

Podrazumevano svi domeni rade samo na `http://`. HTTPS se uključuje jednom po
računaru:

```bash
task tls-init
```

Skripta radi isto na Linuxu i na Windows-u (WSL2):

| Korak | Linux | Windows (WSL2) |
| --- | --- | --- |
| mkcert | Koristi instalirani ili ga preuzima u `~/.local/bin` | Isto, unutar WSL-a |
| Lokalni CA | `mkcert -install` (sudo); instalira i `libnss3-tools` da bi Chrome i Firefox verovali CA-u | `mkcert -install` u WSL-u, pa uvoz istog CA-a u Windows skladište korisnika; Windows jednom pita za potvrdu (*Security Warning* → *Yes*) |
| Sertifikat | Za sve domene iz `scripts/helpers/projects.list`, u `containers/k-local/tls/` | Isto |
| nginx | Restart `k-local`, sluša i na 443 | Isto; Windows browser dolazi preko WSL localhost prosleđivanja |

Posle toga restartuj browser i otvori npr. `https://k-auth.local`. HTTP i
dalje radi. Ponovi `task tls-init` kad dodaš novi projekat (novi domen ulazi u
sertifikat). Sertifikati i privatni ključ se ne komituju (`.gitignore`), a CA
(`mkcert -CAROOT`) ostaje samo na tvom računaru i ne deli se.

Firefox na Windows-u koristi Windows skladište ako je u `about:config`
uključeno `security.enterprise_roots.enabled` (u novijim verzijama jeste).

Ručni uvoz CA-a u Windows, ako automatski ne uspe: u WSL-u
`explorer.exe "$(wslpath -w "$(mkcert -CAROOT)")"`, dupli klik na
`rootCA.pem` → *Install Certificate* → *Current User* → *Place all
certificates in the following store* → *Trusted Root Certification
Authorities*.

## Servisi

| Servis | Šta je | Gde |
| --- | --- | --- |
| `k-local` | nginx, ulaz za sve `*.local` domene | port 80 |
| `k-invoice-db` | PostgreSQL 18, baza faktura | `localhost:5432` |
| `k-master-db` | MariaDB, `office_master` (licence, korisnici po licenci, auth, subjekti) | `localhost:3306` |
| `k-license-1-db` | MariaDB, server licenci 1 (`office_licenca`) | `localhost:3308` |
| `k-license-2-db` | MariaDB, server licenci 2 (`office_licenca3`) | `localhost:3309` |
| `k-redis` | Redis 7 | `localhost:6379` |
| `k-auth` | auth servis (Laravel, repo `kancelarko`) | http://k-auth.local |
| `k-auth-worker` | red poslova auth servisa (odjava ka modulima) | — |
| `k-fakture` | k-fakture (Laravel) | http://k-fakture.local |
| `k-gateway` | k-gateway (Kotlin, Spring Boot) | http://k-gateway.local |

Portovi, putanje projekata i pristupni podaci baze menjaju se u `.env`;
sve opcije su u `.env.example`.

```bash
task services                         # meni: posle Enter rade tačno označeni, bez dodavanja zavisnosti
task services -- all                  # samo podiže (sa zavisnostima), ništa ne gasi
task services -- k-fakture k-gateway  # po nazivu ili rednom broju: task services -- 1 3
docker compose up -d                  # podigni sve
docker compose up -d k-fakture        # samo jedan servis, sa zavisnostima
docker compose up -d --build          # posle izmene Dockerfile-a
docker compose ps
docker compose logs -f k-gateway
docker compose restart k-gateway      # posle izmene koda
docker compose down                   # ugasi sve, podaci u bazama ostaju
```

## k-fakture

U `.env` projekta:

```text
DB_HOST=k-invoice-db
REDIS_HOST=k-redis
```

Ako je projekat kloniran pod drugim imenom, u `.env` k-docker-a dodaj npr.
`K_FAKTURE_PATH=../k-fakture-backend`.

```bash
docker compose up -d k-fakture
docker compose exec k-fakture composer install
docker compose exec k-fakture artisan migrate
docker compose exec k-fakture artisan storage:link --relative
```

Izmene PHP koda vide se odmah. JS i CSS se grade pri startu kontejnera, pa
posle izmene fronta `docker compose restart k-fakture`. Za sada nema `queue`,
`scheduler`, `vite` i Xdebug-a.

## Baze za auth (office_master + licence)

`k-master-db` drži `office_master`, a `k-license-1-db` i `k-license-2-db` su
dva servera licenci (u produkciji `license_srvN`). U `office_license` je
`DBHost` ime servisa, pa iz kontejnera konekcija radi direktno.

Baze se pune iz SQL dump-ova koji nisu u ovom repou (`K_DB_DUMPS_PATH` u
`.env`, podrazumevano `../rokovnik/docker/db`):

```bash
task db-seed                  # uvozi samo u prazne baze + test korisnici
task db-seed -- --force       # briše i ponovo uvozi office_master i obe licence
task db-seed -- --local       # samo licence i test korisnici (scripts/seed/*.sql)
```

Svako pokretanje pravi i praznu bazu `office_licenca4` za **slobodnu licencu 4**
(appCode `KAUT-TEST-REGI-0004`) — za probu registracije; ponovni seed je vraća u slobodno stanje.

```text
```

Dump-ovi su iz MySQL 5.7; skripta u letu ispravlja ono što MariaDB 12 ne
prihvata (vidi `mysql57_compat` u `scripts/db-seed.sh`).

| Licenca | Server | Baza | Firma |
| --- | --- | --- | --- |
| 1 | `k-license-1-db` | `office_licenca` | Firma Licenca 1 |
| 3 | `k-license-2-db` | `office_licenca3` | Firma Licenca 3 |

Test korisnici (lozinka `password`):

| Korisnik | Licence | Za test |
| --- | --- | --- |
| `multi@k-auth.local` | 1 (SADMIN), 3 (USER) | ista lozinka na obe → izbor licence |
| `multi.razlicita@k-auth.local` | 1, 3 | lozinka važi samo na 1 (na 3 je `drugalozinka`) → licenca 1 bez izbora |
| `single@k-auth.local` | 1 (ADMIN) | jedna licenca |

2FA za licencu se uključuje u `office_master.office_license.login_2fa`.

## k-auth

Auth servis (SSO/SLO), repo `kancelarko`. `.env` projekta je podešen za rad
sa hosta (`artisan`, tinker na `127.0.0.1` i objavljenim portovima):

```text
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=office_master
TENANT_DB_HOST_MAP="k-license-1-db=127.0.0.1:3308,k-license-2-db=127.0.0.1:3309"
```

U kontejneru compose prepisuje `DB_HOST`, `REDIS_HOST` i prazni
`TENANT_DB_HOST_MAP`, pa se koriste imena servisa.

```bash
task db-seed
docker compose up -d k-auth k-auth-worker
docker compose exec k-auth artisan tinker scripts/tinker-connection-manager.php
```

`k-auth-worker` obrađuje red poslova auth servisa (back-channel odjava ka
modulima). Posle izmene koda: `docker compose restart k-auth-worker`.

## k-gateway

```bash
docker compose up -d k-gateway
docker compose logs -f k-gateway      # prvi start skida Gradle i zavisnosti, par minuta
docker compose restart k-gateway      # posle izmene koda
```

Rute ka adresaru i delovodniku rade tek kad i ti servisi budu u k-docker-u.

## Novi projekat

1. Dodaj red `ime URL domen` u `scripts/helpers/projects.list`.
2. Dodaj servis u `docker-compose.yaml`, a Dockerfile u `containers/<ime>/image/`.
3. Dodaj `containers/k-local/conf.d/<ime>.conf`: za PHP-FPM aplikaciju kopiraj
   `k-fakture.conf` i dodaj mount koda u servis `k-local`, za sve ostalo
   kopiraj `k-gateway.conf`.
4. `docker compose up -d k-local`

## Ako nešto ne radi

| Problem | Šta uraditi |
| --- | --- |
| `task: command not found` | Instaliraj Task u Linux/WSL okruženju |
| `task services` javlja da terminal nije interaktivan | Pokreni iz običnog terminala ili navedi servise: `task services -- k-fakture` |
| Kloniranje puca (`Authentication failed`) | Umesto lozinke koristi Personal Access Token |
| Domen ne radi, a u WSL-u radi | Unos nedostaje u Windows hosts fajlu: ponovi `task projects-init` i potvrdi UAC, ili ga dodaj ručno u `C:\Windows\System32\drivers\etc\hosts` kao administrator |
| `k-local` odmah staje, `bind() to 0.0.0.0:80 failed` | Port 80 drži drugi proces, najčešće Apache |
| `https://…` ne odgovara, `http://` radi | HTTPS nije uključen na ovom računaru: `task tls-init` |
| Browser javlja `NET::ERR_CERT_AUTHORITY_INVALID` | CA nije u skladištu browsera: ponovi `task tls-init` (na Windows-u potvrdi *Security Warning*), pa restartuj browser; Linux: proveri da je instaliran `libnss3-tools` |
| Browser javlja `NET::ERR_CERT_COMMON_NAME_INVALID` za novi domen | Domen je dodat posle pravljenja sertifikata: `task tls-init` |
| `k-local` staje, `bind() to 0.0.0.0:443 failed` | Port 443 drži drugi proces (Apache, IIS, Skype…): ugasi ga ili privremeno obriši `containers/k-local/tls/listen-443.conf` |
| `*.local` vraća 502 | Kontejner aplikacije ne radi ili još kompajlira: `docker compose ps`, `docker compose logs -f <servis>` |
| `docker compose up` javlja da putanja `../k-fakture` ne postoji | Projekat nije kloniran ili je drugačije nazvan: `task projects-init` ili `K_FAKTURE_PATH` u `.env` |
| Laravel: `getaddrinfo for redis failed` ili `Connection refused` ka bazi | Proveri `DB_HOST` i `REDIS_HOST` u `.env` projekta i da su baze (`k-invoice-db`, `k-master-db`, `k-license-*-db`) i `k-redis` podignute |
| `Permission denied` na fajlovima koje kontejner pravi | Tvoj uid nije 1000: `docker compose build --build-arg HOST_UID=$(id -u) --build-arg HOST_GID=$(id -g)` |
