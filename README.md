# k-docker

Zajednički alat za postavljanje lokalnog razvojnog okruženja kompanijskih
projekata. Trenutno sadrži jednu komandu, `task projects-init`, koja klonira
odabrane projekte pored ovog repozitorijuma i upisuje njihove lokalne domene u
hosts fajl.

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

## Rešavanje problema

| Problem | Postupak |
| --- | --- |
| `task: command not found` | Instalirajte Task v3 u Linux/WSL okruženju i proverite `task --version` |
| Kloniranje projekta ne uspeva (`Authentication failed`, `repository not found`) | Proverite URL u `scripts/helpers/projects.list` i pristup repozitorijumu; za privatne repozitorijume koristite Personal Access Token umesto lozinke |
| `task projects-init` javlja da terminal nije interaktivan | Pokrenite komandu iz običnog terminala ili zadajte brojeve: `task projects-init -- 1 2` |
| Hosts unosi nisu dodati (sudo odbijen, UAC otkazan, `powershell.exe` nedostupan) | Dodajte ispisane redove ručno: Linux/WSL `sudo nano /etc/hosts`, Windows Notepad kao administrator nad `C:\Windows\System32\drivers\etc\hosts`; zatim ponovite `task projects-init` |
| `k-gateway.local` radi u WSL-u, ali ne iz Windows browsera | Unos nedostaje u Windows hosts fajlu; ponovite `task projects-init` i potvrdite UAC prozor ili dodajte red ručno |

## Provere

`task projects-init` je proveren na Linux-u u privremenom direktorijumu:
interaktivni meni (strelice, razmak, `a`, `q`, Enter), izbor brojevima i `all`,
HTTPS kloniranje oba projekta, preskakanje postojećih direktorijuma i poruka za
neinteraktivan terminal. Upis u hosts je proveren nad privremenim fajlom:
dodavanje, fajl bez završnog reda, CRLF fajl, postojeći unos drugim veličinama
slova, sudo grana i odbijen sudo. **Upis u Windows hosts iz WSL-a nije praktično
testiran.**
