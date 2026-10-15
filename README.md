# k-docker

Zajednički alat za postavljanje lokalnog razvojnog okruženja kompanijskih
projekata. Sadrži komandu `task projects-init`, koja klonira odabrane projekte
pored ovog repozitorijuma i upisuje njihove lokalne domene u hosts fajl, i
`docker-compose.yaml` sa zajedničkim servisima: bazom za licence (`k-licence-db`),
nginx reverse proxy-jem (`k-local`) koji lokalne domene vodi na aplikacije i
kontejnerom aplikacije k-fakture (`k-fakture`).

## Preduslovi

| Linux | Windows |
| --- | --- |
| Git, Bash i Task v3 | WSL2 sa Git-om, Bash-om i Task-om v3 instaliranim **unutar WSL-a** |
| `sudo` za upis u `/etc/hosts` | Administratorska prava na Windows-u za upis u Windows hosts fajl |

Uputstva za instalaciju: [Task](https://taskfile.dev/docs/installation),
[WSL2](https://learn.microsoft.com/windows/wsl/install).

Na Windows-u sve komande izvršavaju se u WSL terminalu. Repozitorijume držite u
Linux filesystem-u, npr. `~/Kancelarko/k-docker`, umesto u `/mnt/c/...`.

## Kloniranje projekata

Lista dostupnih projekata nalazi se u `scripts/helpers/projects.list`, jedan projekat po redu u
obliku `ime URL lokalni-domen`:

```text
k-gateway https://github.com/zivojindavidovic/k-gateway k-gateway.local
```

Ime je ujedno naziv direktorijuma u koji se projekat klonira, a lokalni domen se
upisuje u hosts fajl. Novi projekat se dodaje novim redom; domen se može
izostaviti ako projektu nije potreban.

```bash
task projects-init
```

Komanda prikazuje numerisanu listu projekata. Strelicama ili tasterima `j`/`k`
pomerate kursor, razmakom označavate ili poništavate projekat, `a` označava sve,
Enter potvrđuje izbor, a `q` odustaje. Kloniraju se samo označeni projekti,
preko HTTPS-a, u direktorijum pored `k-docker`, npr. `~/Kancelarko/k-gateway`.
Već klonirani projekti su obeleženi u listi i preskaču se; postojeći
direktorijumi se ne menjaju.

Izbor se može zadati i brojevima, bez interaktivnog menija:

```bash
task projects-init -- 1 2
task projects-init -- all
```

Za privatne repozitorijume Git traži GitHub korisničko ime i Personal Access
Token umesto lozinke; da ih ne unosite pri svakom kloniranju, podesite
`git config --global credential.helper store`.

Posle kloniranja komanda za svaki odabrani projekat obezbeđuje red
`127.0.0.1 <domen>` u `/etc/hosts`, da bi `http://k-gateway.local` i
`http://k-fakture.local` vodili na lokalni računar. Upis traži sudo lozinku;
postojeći unosi se ne dupliraju, a unos dobijaju i već klonirani projekti.
U WSL-u se isti redovi dodaju i u Windows fajl
`C:\Windows\System32\drivers\etc\hosts` kroz PowerShell; Windows prikazuje UAC
prozor koji treba potvrditi, inače domeni ne rade iz Windows browsera. WSL pri
svakom pokretanju generiše svoj `/etc/hosts` iz Windows fajla, pa unosi ostaju i
posle `wsl --shutdown`. Ako upis ne uspe, komanda ispisuje redove koje treba
ručno dodati: na Linux-u u `/etc/hosts` uz `sudo`, na Windows-u u navedeni fajl
otvoren u Notepad-u pokrenutom kao administrator.

## k-local (nginx)

Servis `k-local` (nginx) iz `docker-compose.yaml` zamenjuje Apache instaliran na
hostu. Prima zahteve na portu 80 i po domenu ih:

- prosleđuje aplikacijama koje se vrte na hostu ili objavljuju HTTP port
  (`proxy_pass`), ili
- sam servira, kad je aplikacija PHP-FPM kontejner iz ovog compose fajla:
  statičke fajlove čita iz koda projekta mount-ovanog read-only na
  `/srv/<ime>`, a PHP izvršava preko FastCGI-ja (`fastcgi_pass`) na portu koji
  kontejner objavljuje na `127.0.0.1`. Tako radi `k-fakture.local`.

Kontejner radi sa `network_mode: host`, pa `127.0.0.1` u konfiguraciji znači
loopback hosta.

```bash
docker compose up -d k-local
```

Pre pokretanja port 80 mora biti slobodan. Ako na hostu radi Apache, ugasite ga:

```bash
sudo systemctl disable --now apache2
```

Konfiguracija je u `containers/k-local/conf.d/`, jedan fajl po projektu.
`00-default.conf` vraća 404 za domene koji nemaju svoj fajl. Novi PHP-FPM
projekat se dodaje kopiranjem `k-fakture.conf` pod novim imenom, uz izmenu
`server_name`, `root` i porta u `fastcgi_pass`, i dodavanjem mount-a koda na
`/srv/<ime>` u servisu `k-local`. Aplikacija koja se vrti na hostu dobija samo
proxy blok:

```nginx
server {
    listen 80;
    server_name k-gateway.local;
    location / {
        proxy_pass http://127.0.0.1:9090;
        proxy_set_header Host $host;
    }
}
```

Posle izmene:

```bash
docker compose up -d k-local      # novi mount
docker compose restart k-local    # samo izmena conf fajla
```

Logovi pristupa i grešaka idu u izlaz kontejnera: `docker compose logs -f k-local`.

Na Windows-u `network_mode: host` radi sa Docker Engine-om instaliranim unutar
WSL-a. Docker Desktop ga podržava tek uz opciju *Enable host networking* u
podešavanjima (Resources > Network).

## k-fakture

Servis `k-fakture` je PHP-FPM kontejner aplikacije k-fakture, nastao iz `php`
servisa u `docker-compose.yaml` tog projekta, s tim što umesto `php:8.5-apache`
koristi `php:8.5-fpm`: web server je `k-local`, a kontejner samo izvršava PHP.
Dockerfile (sa ugrađenim entrypoint-om) je u `containers/k-fakture/image/`,
`php.ini` u `containers/k-fakture/`. Build kontekst je direktorijum projekta,
pa važi njegov `.dockerignore`; isti direktorijum je bind mount na
`/var/www/html`, pa se izmene vide odmah. Projekat mora biti kloniran pored
`k-docker` (`task projects-init`), a ovaj repozitorijum pod imenom `k-docker`,
jer Dockerfile putanja ide relativno od projekta. Ako je direktorijum projekta
drugačije nazvan, putanju zadajte u `.env`:

```text
K_FAKTURE_PATH=../k-fakture-backend
```

```bash
docker compose up -d --build k-fakture k-local
docker compose exec k-fakture composer install
docker compose exec k-fakture artisan migrate
```

Aplikacija je dostupna samo kroz `k-local`, na `http://k-fakture.local`.
FastCGI port `K_FAKTURE_PORT` (podrazumevano 9082) nije HTTP, služi samo
`k-local`-u. Ako port promenite, promenite ga i u
`containers/k-local/conf.d/k-fakture.conf`. Entrypoint pri startu instalira
node zavisnosti i pokreće `npm run build`, pa `k-local` servira izgrađene
asset-e iz `public/build`. `php artisan storage:link` pokrećite sa
`--relative`, jer apsolutni link na `/var/www/html/...` u `k-local` ne postoji.

Baza i Redis su zajednički servisi za sve projekte: `k-master-db` (PostgreSQL
18, Dockerfile sa healthcheck-om u `containers/k-master-db/image/`, prenet iz
compose fajla projekta) i `k-redis`. U `.env` projekta zato stoji
`DB_HOST=k-master-db` i `REDIS_HOST=k-redis`; početna baza, korisnik, lozinka
i lokalni portovi zadaju se kroz `K_MASTER_DB_*` i `K_REDIS_PORT` u `.env`
k-docker-a. Podaci su u volumenima `k-docker_k-master-db-data` i
`k-docker_k-redis-data`.

Gateway saobraćaj ka `https://kancelarko.local` ide kontejner-na-kontejner,
pa radi tek kad i kancelarko bude servis u ovom compose fajlu (zajednička
`default` mreža); do tada pozivi ka gateway-u iz kontejnera ne prolaze.

`www-data` u kontejneru ima uid/gid 1000 (podrazumevano iz Dockerfile-a), da
fajlovi nastali u kontejneru budu vaše vlasništvo; ako vaš uid nije 1000:

```bash
docker compose build --build-arg HOST_UID=$(id -u) --build-arg HOST_GID=$(id -g) k-fakture
```

Još nisu preneti servisi `queue`, `scheduler` i `vite`, pa se queue poslovi
(izdavanje faktura) ne izvršavaju, a asset-i se grade jednom pri startu
kontejnera umesto kroz HMR. Xdebug (ekstenzija i podešavanja u `php.ini`) je
izostavljen i dodaje se kad zatreba.

## Rešavanje problema

| Problem | Postupak |
| --- | --- |
| `task: command not found` | Instalirajte Task v3 u Linux/WSL okruženju i proverite `task --version` |
| Kloniranje projekta ne uspeva (`Authentication failed`, `repository not found`) | Proverite URL u `scripts/helpers/projects.list` i pristup repozitorijumu; za privatne repozitorijume koristite Personal Access Token umesto lozinke |
| `task projects-init` javlja da terminal nije interaktivan | Pokrenite komandu iz običnog terminala ili zadajte brojeve: `task projects-init -- 1 2` |
| Hosts unosi nisu dodati (sudo odbijen, UAC otkazan, `powershell.exe` nedostupan) | Dodajte ispisane redove ručno: Linux/WSL `sudo nano /etc/hosts`, Windows Notepad kao administrator nad `C:\Windows\System32\drivers\etc\hosts`; zatim ponovite `task projects-init` |
| `k-local` kontejner odmah staje, u logu `bind() to 0.0.0.0:80 failed (98: Address already in use)` | Port 80 drži drugi proces, najčešće Apache: `sudo systemctl disable --now apache2`, zatim `docker compose up -d k-local` |
| `docker compose build k-fakture` javlja da putanja `../k-fakture` ne postoji | Projekat nije kloniran pored `k-docker` ili je direktorijum drugačije nazvan; `task projects-init` ili `K_FAKTURE_PATH=...` u `.env` |
| `k-fakture.local` vraća 502 Bad Gateway | `k-fakture` kontejner ne radi ili sluša na drugom portu: `docker compose ps`, `docker compose logs k-fakture`; `K_FAKTURE_PORT` u `.env` i `fastcgi_pass` u `containers/k-local/conf.d/k-fakture.conf` moraju biti isti |
| `File not found.` u browseru, `Primary script unknown` u logu `k-local` | Kod projekta nije na očekivanim putanjama: `/srv/k-fakture` u `k-local` i `/var/www/html` u `k-fakture`; proverite `K_FAKTURE_PATH` i `docker compose up -d k-local` posle izmene mount-a |
| Laravel javlja `getaddrinfo for redis failed` ili `Connection refused` ka bazi | U `.env` projekta mora biti `DB_HOST=k-master-db` i `REDIS_HOST=k-redis`; `docker compose ps` da su `k-master-db` i `k-redis` podignuti |
| `k-gateway.local` radi u WSL-u, ali ne iz Windows browsera | Unos nedostaje u Windows hosts fajlu; ponovite `task projects-init` i potvrdite UAC prozor ili dodajte red ručno |

## Provere

`task projects-init` je proveren na Linux-u u privremenom direktorijumu:
interaktivni meni (strelice, razmak, `a`, `q`, Enter), izbor brojevima i `all`,
HTTPS kloniranje oba projekta, preskakanje postojećih direktorijuma i poruka za
neinteraktivan terminal. Upis u hosts je proveren nad privremenim fajlom:
dodavanje, fajl bez završnog reda, CRLF fajl, postojeći unos drugim veličinama
slova, sudo grana i odbijen sudo. **Upis u Windows hosts iz WSL-a nije praktično
testiran.**
