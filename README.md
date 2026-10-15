# k-docker

Lokalno razvojno okruženje za Kancelarko projekte. Jedan `docker compose`
drži zajedničke servise (nginx, PostgreSQL, Redis, MariaDB za licence) i
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

## Servisi

| Servis | Šta je | Gde |
| --- | --- | --- |
| `k-local` | nginx, ulaz za sve `*.local` domene | port 80 |
| `k-master-db` | PostgreSQL 18, zajednička baza | `localhost:5432` |
| `k-redis` | Redis 7 | `localhost:6379` |
| `k-licence-db` | MariaDB, baza licenci | `localhost:3308` |
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
DB_HOST=k-master-db
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
| `*.local` vraća 502 | Kontejner aplikacije ne radi ili još kompajlira: `docker compose ps`, `docker compose logs -f <servis>` |
| `docker compose up` javlja da putanja `../k-fakture` ne postoji | Projekat nije kloniran ili je drugačije nazvan: `task projects-init` ili `K_FAKTURE_PATH` u `.env` |
| Laravel: `getaddrinfo for redis failed` ili `Connection refused` ka bazi | Proveri `DB_HOST` i `REDIS_HOST` u `.env` projekta i da su `k-master-db` i `k-redis` podignuti |
| `Permission denied` na fajlovima koje kontejner pravi | Tvoj uid nije 1000: `docker compose build --build-arg HOST_UID=$(id -u) --build-arg HOST_GID=$(id -g)` |
