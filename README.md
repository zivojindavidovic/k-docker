# k-docker

Lokalno okruženje za Kancelarko projekte. Projekti se kloniraju pored ovog
repoa (`~/Kancelarko/<projekat>`), a ovde su svi kontejneri, nginx, baze i
Redis.

## Šta ti treba

- Ubuntu ili Windows sa [WSL2](https://learn.microsoft.com/windows/wsl/install) (Ubuntu). Na Windows-u sve radiš iz WSL terminala, a repoe držiš u `~/Kancelarko`, ne u `/mnt/c`.
- Git, [Docker](https://docs.docker.com/engine/install/ubuntu/) sa Compose plugin-om i [Task](https://taskfile.dev/docs/installation).
- [SSH ključ na GitHub-u](https://docs.github.com/en/authentication/connecting-to-github-with-ssh). Bez njega se klonira preko HTTPS-a sa Personal Access Token-om.
- Slobodni portovi 80 i 443. Ako radi Apache: `sudo systemctl disable --now apache2`.

## Prvo podizanje

```bash
git clone git@github.com:zivojindavidovic/k-docker.git ~/Kancelarko/k-docker
cd ~/Kancelarko/k-docker
cp .env.example .env
task projects
```

`task projects` klonira `k-auth` i `k-gateway` (obavezni su, ne mogu da se
odznače) i projekte koje označiš. Već klonirani su označeni, imaju zelenu
lampicu i ne kloniraju se ponovo. Ko nema SSH ključ, označi „Kloniraj preko
HTTPS-a”.

Baze za auth se pune iz dump-ova iz `rokovnik` projekta. Nisu u ovom repou jer
imaju stvarne podatke:

```bash
cp <rokovnik>/docker/db/office-*-init*.sql scripts/seed/
task db-init
```

`k-auth` se podešava jednom:

```bash
cp ../kancelarko/.env.example ../kancelarko/.env
docker compose run --rm --no-deps k-auth composer install
docker compose run --rm --no-deps k-auth artisan key:generate
docker compose run --rm --no-deps k-auth artisan auth:keys-generate
docker compose run --rm --no-deps k-auth artisan auth:client-secret k-gateway
```

`auth:keys-generate` ispiše `OAUTH_SIGNING_KID`, a `auth:client-secret` heš
tajne. Oba idu u `../kancelarko/.env`. Samu tajnu upiši u
`K_GATEWAY_CLIENT_SECRET` u `.env` ovog repoa.

Na kraju:

```bash
task services
```

Prvi put traži sudo lozinku (na Windows-u i UAC potvrdu) jer upisuje domene u
hosts i pravi lokalni HTTPS sertifikat. Restartuj browser i otvori
https://auth.kancelarko.local. Prvi start `k-gateway`-a traje par minuta jer
Gradle skida zavisnosti (`docker compose logs -f k-gateway`).

## k-fakture

Build traži i `k-gateway-client` pored ostalih projekata:

```bash
git clone git@github.com:zivojindavidovic/k-gateway-client.git ../k-gateway-client
```

U `.env` projekta stavi `DB_HOST=k-invoice-db` i `REDIS_HOST=k-redis`. Ako je
projekat u drugom folderu, promeni `K_FAKTURE_PATH` u `.env` ovog repoa. Zatim:

```bash
docker compose up -d k-fakture
docker compose exec k-fakture composer install
docker compose exec k-fakture artisan migrate
docker compose exec k-fakture artisan storage:link --relative
```

JS i CSS se grade pri startu kontejnera, pa posle izmene fronta uradi
`docker compose restart k-fakture`.

## Svakodnevno

```bash
task services                    # meni: šta radi, šta se gasi
task projects                    # kloniraj još neki projekat
task db-init -- --local          # vrati test korisnike na početno stanje
task db-init -- --force          # ponovo uvezi baze iz dump-ova
task hosts                       # upiši domene u hosts
task tls                         # napravi ponovo HTTPS sertifikat
docker compose logs -f k-gateway
docker compose restart k-gateway # posle izmene koda; isto za k-auth-worker
```

U meniju `task services` obavezni servisi su uvek uključeni, a „Ugasi sve
servise” gasi i njih. `task services` sam upisuje nove domene u hosts i pravi
novi sertifikat kad zatreba.

## Adrese

| Šta | Gde |
| --- | --- |
| k-auth | https://auth.kancelarko.local |
| k-gateway | https://gateway.kancelarko.local |
| k-fakture (kroz gateway) | https://fakture.kancelarko.local |
| RedisInsight | https://redisinsight.kancelarko.local |
| office_master (MariaDB) | `localhost:3306` |
| licence 1 i 3 (MariaDB) | `localhost:3308`, `localhost:3309` |
| fakture (PostgreSQL) | `localhost:5432` |
| Redis | `localhost:6379` |

Portovi se menjaju u `.env`.

## Test korisnici

Lozinka je svuda `password`. Licenca 1 je „Paragraf Licenca 1” na
`k-license-1-db`, licenca 3 je „Paragraf Licenca 3” na `k-license-2-db`.

| Korisnik | Licence | Šta se vidi |
| --- | --- | --- |
| `developer-1@paragraf.rs` | 1 (SADMIN), 3 (USER) | izbor licence |
| `developer-2@paragraf.rs` | 1, 3 (na 3 lozinka `drugalozinka`) | ulazi direktno u licencu 1 |
| `developer-3@paragraf.rs` | 1 (ADMIN) | prijava bez izbora |
| `developer-4@paragraf.rs` | 1, 3 (na 3 arhiviran) | licenca 3 je siva |
| `developer-5@paragraf.rs` | 1 | suspendovan 7 dana |
| `developer-6@paragraf.rs` | 1 | nalog nije aktivan |
| `developer-7@paragraf.rs` | 1 | email nije potvrđen |
| `developer-8@paragraf.rs` | 1 | traži prihvatanje uslova |

Licenca 4 (appCode `KAUT-TEST-REGI-0004`) je slobodna, za probu registracije.
Svaki `task db-init` je ponovo oslobađa. 2FA se uključuje u
`office_master.office_license.login_2fa`.

## Kako je povezano

- Sve ide kroz `k-local` (nginx). Aplikacije su iza `k-gateway`-a: on radi prijavu na `k-auth`-u i prosleđuje zahtev aplikaciji sa tokenom.
- Kontejneri su u istoj Docker mreži i zovu se po imenu servisa (`k-gateway:9090`, `k-auth:9000`). Javni domeni su aliasi `k-local`-a, pa ih i kontejneri dosežu.
- Adrese koje zavise od okruženja (`APP_URL`, OAuth adrese, issuer) postavlja `docker-compose.yaml`. Zbog k-docker-a ne treba menjati `.env` projekata.
- Lokalni domeni su `server_name` iz `containers/k-local/conf.d`. Odatle se pune hosts i HTTPS sertifikat.

## Novi projekat

1. Red `ime URL domen` u `scripts/helpers/projects.list`. Projekat se klonira u `K_<IME>_PATH` iz `.env`, inače u `../<ime>`.
2. Servis u `docker-compose.yaml`, Dockerfile u `containers/<ime>/image/`.
3. Vhost u `containers/k-local/conf.d/<ime>.conf`: za PHP-FPM kopiraj `k-fakture.conf`, za ostalo `k-redisinsight.conf`.
4. `task services`

## Kad nešto ne radi

| Problem | Rešenje |
| --- | --- |
| Kloniranje: `Permission denied (publickey)` | Dodaj SSH ključ na GitHub ili `task projects -- --https` |
| Kloniranje: `Authentication failed` | Umesto lozinke unesi Personal Access Token |
| Domen ne radi u Windows browser-u | `task hosts` i potvrdi UAC |
| Browser javlja da sertifikat nije validan | `task tls`, pa restartuj browser. Na Windows-u potvrdi „Security Warning” |
| `port is already allocated` za 80 ili 443 | Port drži drugi program (Apache, IIS): ugasi ga |
| 502 na nekom domenu | Kontejner ne radi ili se još podiže: `docker compose ps`, `docker compose logs -f <servis>` |
| `task services` kaže da terminal nije interaktivan | Pokreni iz običnog terminala ili navedi servise: `task services -- k-fakture` |
