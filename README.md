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
Ubuntu-om, pa unutar WSL-a isto što i gore (radi i sa Docker Desktop-om).
Sve komande kucaš u WSL terminalu, a repozitorijume držiš u Linux fajl
sistemu (`~/Kancelarko`), ne u `/mnt/c`.

Portovi 80 i 443 moraju biti slobodni. Ako na mašini radi Apache:

```bash
sudo systemctl disable --now apache2
```

## Prvo pokretanje

```bash
git clone <url> ~/Kancelarko/k-docker   # direktorijum mora da se zove k-docker
cd ~/Kancelarko/k-docker
cp .env.example .env
task projects                           # izaberi projekte
task services                           # izaberi servise
```

`task projects` prikazuje projekte iz `scripts/helpers/projects.list` i da li
su već klonirani (zelena lampica); klonirani ne mogu ponovo da se izaberu.
`k-auth` i `k-gateway` su obavezni (`required_projects` u
`scripts/projects.sh`) i uvek se kloniraju ako nedostaju. Projekat se klonira
u putanju iz `K_<IME>_PATH` u `.env` (npr. `k-auth` → `K_AUTH_PATH=../kancelarko`),
a bez tog reda u `../<ime>`; ista putanja se proverava kao „već klonirano”.
Na kraju piše koliko je projekata uspešno klonirano i zašto ostali nisu
(npr. nema SSH ključa ili pristupa repozitorijumu).

`task projects` i `task services` (kad pokreće `k-local`) upisuju sve lokalne
domene u hosts fajl: svaki `server_name` iz `containers/k-local/conf.d`, pa
novi vhost ne traži ručni unos. Isto radi i `task hosts`. Linux traži sudo
lozinku samo kad neki domen nedostaje; Windows (WSL) tada otvara i UAC prozor
koji treba potvrditi, inače domeni ne rade iz Windows browsera.

Kloniranje ide preko SSH-a i traži [SSH ključ dodat na GitHub nalog](https://docs.github.com/en/authentication/connecting-to-github-with-ssh).
Ko nema SSH ključ, u meniju označi „Kloniraj preko HTTPS-a” (ili doda
`--https`); tada privatni repozitorijumi traže GitHub korisničko ime i
Personal Access Token, a `git config --global credential.helper store` ih pamti.

Bez menija:

```bash
task projects -- all                  # svi projekti koji nisu klonirani
task projects -- k-fakture            # po nazivu ili rednom broju iz liste; obavezni se uvek dodaju
task projects -- --https k-fakture    # preko HTTPS-a umesto SSH-a
```

Posle prvog `task services` pogledaj sekciju projekta ispod, jer neki traže
još koji korak.

## HTTPS (lokalno)

Svi domeni rade na `https://`, a `http://` se preusmerava na HTTPS. `task
services` sam pokreće `task tls` kad sertifikat ne postoji ili ne pokriva
sve domene (npr. posle dodavanja vhost-a); može i ručno:

```bash
task tls
```

Skripta radi isto na Linuxu i na Windows-u (WSL2):

| Korak | Linux | Windows (WSL2) |
| --- | --- | --- |
| mkcert | Koristi instalirani ili ga preuzima u `~/.local/bin` | Isto, unutar WSL-a |
| Lokalni CA | `mkcert -install` (sudo); instalira i `libnss3-tools` da bi Chrome i Firefox verovali CA-u | `mkcert -install` u WSL-u, pa uvoz istog CA-a u Windows skladište korisnika; Windows jednom pita za potvrdu (*Security Warning* → *Yes*) |
| Sertifikat | Za sve `server_name` domene iz `containers/k-local/conf.d`, u `containers/k-local/tls/` | Isto |
| nginx | Reload `k-local`: sluša i na 443, HTTP preusmerava na HTTPS | Isto; Windows browser dolazi preko WSL localhost prosleđivanja |

Posle prvog pokretanja restartuj browser i otvori npr. `https://auth.kancelarko.local`.
Sertifikati i privatni ključ se ne komituju (`.gitignore`), a CA
(`mkcert -CAROOT`) ostaje samo na tvom računaru i ne deli se. Kopija CA
sertifikata (`containers/k-local/tls/rootCA.crt`) se montira u `k-gateway`
(`/certificates`, `USE_SYSTEM_CA_CERTS`), da bi gateway verovao
`https://auth.kancelarko.local` kad iz kontejnera razmenjuje tokene.

Upozorenje „Not secure” na HTTPS-u znači da sertifikat ne pokriva taj domen
(pokreni `task tls`) ili da stranica učitava nešto preko `http://`.

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
| `k-local` | nginx, ulaz za sve `*.local` domene | portovi 80 i 443 |
| `k-invoice-db` | PostgreSQL 18, baza faktura | `localhost:5432` |
| `k-master-db` | MariaDB, `office_master` (licence, korisnici po licenci, auth, subjekti) | `localhost:3306` |
| `k-license-1-db` | MariaDB, server licenci 1 (`office_licenca`) | `localhost:3308` |
| `k-license-2-db` | MariaDB, server licenci 2 (`office_licenca3`) | `localhost:3309` |
| `k-redis` | Redis 7 | `localhost:6379` |
| `k-redisinsight` | RedisInsight, pregled Redis-a (keš, redovi, sesije); konekcija `k-redis` je unapred podešena | https://redisinsight.kancelarko.local |
| `k-auth` | auth servis (Laravel, repo `kancelarko`) | https://auth.kancelarko.local |
| `k-auth-worker` | red poslova auth servisa (odjava ka modulima) | — |
| `k-fakture` | k-fakture (Laravel, PHP-FPM) | https://fakture.kancelarko.local (preko gateway-a) |
| `k-gateway` | k-gateway (Kotlin, Spring Boot): prijava (BFF), tokeni, ulaz za aplikacije | https://gateway.kancelarko.local |

Aplikacije su iza gateway-a: `k-auth ◄── k-gateway ──► aplikacije`. k-auth zna samo za gateway
(jedan klijent), aplikacije znaju samo za gateway. Browser ide na `fakture.kancelarko.local`,
k-local ga šalje gateway-u, gateway (posle prijave na k-auth-u) prosleđuje zahtev sa
`Authorization: Bearer` na interni vhost k-local-a (`k-local:9180`, port se ne objavljuje), a on na k-fakture. Nova aplikacija: domen u `kancelarko-apps.conf` i
`scripts/helpers/projects.list`, interni vhost na novom portu u k-local-u (kao u `k-fakture.conf`),
ruta u `k-gateway` (`application.properties`).
`http://k-fakture.local` preusmerava na novi domen.

Svi kontejneri su u istoj Docker mreži, pa se zovu po imenu servisa
(`k-gateway:9090`, `k-auth:9000`, `k-redis`); nginx ih traži preko Docker DNS-a
tek pri zahtevu, pa radi i kad neki servis ne radi (tada vraća 502). Javni
domeni (`auth.kancelarko.local` i ostali) su aliasi `k-local`-a u toj mreži, pa
kontejner koji ih zove stiže na nginx kao i browser, bez `extra_hosts`.
Adrese koje zavise od okruženja (`APP_URL`, OAuth adrese gateway klijenta u
k-auth-u, issuer i javne adrese gateway-a) postavlja `docker-compose.yaml`, pa
`.env` projekata ne mora da se menja; back-channel odjava ide direktno na
`http://k-gateway:9090`. Gateway šalje `X-Forwarded-Proto` aplikacijama
(`SPRING_CLOUD_GATEWAY_SERVER_WEBFLUX_TRUSTEDPROXIES`), pa one prave
`https://` linkove.

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

Meni `task services` unapred označava servise koji već rade (i one koji se
restartuju u petlji). `k-local`, `k-auth`, `k-auth-worker`, `k-gateway`,
`k-master-db`, `k-license-1-db` i `k-redis` su uvek označeni i ne mogu da se
isključe; spisak je `required_services` na vrhu `scripts/services.sh`.
Stavka „Ugasi sve servise” na dnu menija gasi sve servise iz compose-a,
uključujući i obavezne (`docker compose stop`). Pored
svakog servisa piše njegovo trenutno stanje i šta će Enter uraditi
(`↑ pokrenuce se`, `↓ zaustavice se`). `⚠ zavisi i od` znači da servis u
compose-u zavisi od neoznačenog servisa, koji se neće sam pokrenuti.

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
task db-init                  # uvozi samo u prazne baze + test korisnici
task db-init -- --force       # briše i ponovo uvozi office_master i obe licence
task db-init -- --local       # samo licence i test korisnici (scripts/seed/*.sql)
```

Svako pokretanje pravi i praznu bazu `office_licenca4` za **slobodnu licencu 4**
(appCode `KAUT-TEST-REGI-0004`) — za probu registracije; ponovni `task db-init` je vraća u slobodno stanje.

Dump-ovi su iz MySQL 5.7; skripta u letu ispravlja ono što MariaDB 12 ne
prihvata (vidi `mysql57_compat` u `scripts/db-init.sh`).

| Licenca | Server | Baza | Firma |
| --- | --- | --- | --- |
| 1 | `k-license-1-db` | `office_licenca` | Paragraf Licenca 1 |
| 3 | `k-license-2-db` | `office_licenca3` | Paragraf Licenca 3 |

Test korisnici (lozinka `password`):

| Korisnik | Licence | Za test |
| --- | --- | --- |
| `developer-1@paragraf.rs` | 1 (SADMIN), 3 (USER) | ista lozinka na obe → izbor licence |
| `developer-2@paragraf.rs` | 1, 3 | lozinka važi samo na 1 (na 3 je `drugalozinka`) → licenca 1 bez izbora |
| `developer-3@paragraf.rs` | 1 (ADMIN) | jedna licenca → prijava bez izbora |
| `developer-4@paragraf.rs` | 1, 3 (na 3 arhiviran) | izbor: jedna prohodna i jedna siva licenca |
| `developer-5@paragraf.rs` | 1, suspendovan još 7 dana | odbijena prijava (`user_suspended`) |
| `developer-6@paragraf.rs` | 1, nalog na licenci nije aktivan | odbijena prijava (`account_inactive`) |
| `developer-7@paragraf.rs` | 1, email nije potvrđen | odbijena prijava (`email_not_verified`) |
| `developer-8@paragraf.rs` | 1, uslovi nisu prihvaćeni | prijava uz `accept_terms` |

`task db-init -- --local` vraća test korisnike na početno stanje.

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
`TENANT_DB_HOST_MAP`, pa se koriste imena servisa. Prepisuje i `APP_URL`
(`https://auth.kancelarko.local`, ujedno issuer) i `OAUTH_CLIENT_K_GATEWAY_*`
adrese (HTTPS adrese gateway-a, back-channel na `http://k-gateway:9090`).

```bash
task db-init
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

1. Dodaj red `ime URL domen` u `scripts/helpers/projects.list`; putanja
   projekta je `K_<IME>_PATH` u `.env` (i `.env.example`), inače `../<ime>`.
2. Dodaj servis u `docker-compose.yaml`, a Dockerfile u `containers/<ime>/image/`.
3. Dodaj `containers/k-local/conf.d/<ime>.conf`: za PHP-FPM aplikaciju kopiraj
   `k-fakture.conf` i dodaj mount koda u servis `k-local`, za sve ostalo
   kopiraj `k-redisinsight.conf` (proxy na `<servis>:<port>`). Ako domen
   zovu i drugi kontejneri, dodaj ga u aliase `k-local`-a u `docker-compose.yaml`.
4. `task services`: upisuje novi domen u hosts, pravi novi sertifikat i
   podiže `k-local`.

## Ako nešto ne radi

| Problem | Šta uraditi |
| --- | --- |
| `task: command not found` | Instaliraj Task u Linux/WSL okruženju |
| `task services` javlja da terminal nije interaktivan | Pokreni iz običnog terminala ili navedi servise: `task services -- k-fakture` |
| Kloniranje puca (`Permission denied (publickey)`) | Dodaj SSH ključ na GitHub nalog ili kloniraj preko HTTPS-a: `task projects -- --https` |
| Kloniranje puca (`Authentication failed`) | Umesto lozinke koristi Personal Access Token |
| Domen ne radi, a u WSL-u radi | Unos nedostaje u Windows hosts fajlu: `task hosts` i potvrdi UAC, ili ga dodaj ručno u `C:\Windows\System32\drivers\etc\hosts` kao administrator |
| `k-local` se ne podiže, `port is already allocated` ili `address already in use` za 80/443 | Port drži drugi proces (Apache, IIS, Skype…): ugasi ga |
| `https://…` ne odgovara, `http://` ne preusmerava | HTTPS nije uključen na ovom računaru: `task tls` |
| Browser javlja `NET::ERR_CERT_AUTHORITY_INVALID` | CA nije u skladištu browsera: ponovi `task tls` (na Windows-u potvrdi *Security Warning*), pa restartuj browser; Linux: proveri da je instaliran `libnss3-tools` |
| Browser javlja `NET::ERR_CERT_COMMON_NAME_INVALID` za novi domen | Domen je dodat posle pravljenja sertifikata: `task tls` |
| `*.local` vraća 502 | Kontejner aplikacije ne radi ili još kompajlira: `docker compose ps`, `docker compose logs -f <servis>` |
| `docker compose up` javlja da putanja `../k-fakture` ne postoji | Projekat nije kloniran ili je drugačije nazvan: `task projects` ili `K_FAKTURE_PATH` u `.env` |
| Laravel: `getaddrinfo for redis failed` ili `Connection refused` ka bazi | Proveri `DB_HOST` i `REDIS_HOST` u `.env` projekta i da su baze (`k-invoice-db`, `k-master-db`, `k-license-*-db`) i `k-redis` podignute |
| `Permission denied` na fajlovima koje kontejner pravi | Tvoj uid nije 1000: `docker compose build --build-arg HOST_UID=$(id -u) --build-arg HOST_GID=$(id -g)` |
