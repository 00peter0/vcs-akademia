# Epizóda 02 — Sudo User + Zakáž Root Login

Vytvor bezpečného používateľa s admin právami a vypni priame prihlásenie cez root. Štandardná prax na každom produkčnom serveri.

---

## Čo skript urobí

1. Opýta sa na meno nového používateľa.
2. Vytvorí používateľa na VPS a pridá ho do skupiny `sudo`.
3. Skopíruje tvoj SSH key na nového používateľa.
4. Otestuje prihlásenie cez nového používateľa.
5. Zakáže prihlásenie cez root v `/etc/ssh/sshd_config`.
6. Otestuje že root login je skutočne zablokovaný.

---

## Požiadavky

- Dokončená **[Epizóda 01](../01-ssh/)** — SSH key login musí fungovať.
- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- VPS kde sa aktuálne prihlasuješ ako **root** cez SSH key.

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/02-sudo-user/setup-sudo-user.sh
bash setup-sudo-user.sh
```

---

## Po spustení

Prihlásenie cez nového používateľa:

```bash
ssh novy-user@ip
```

Root login je **zablokovaný** — `ssh root@ip` už neprejde, ani s kľúčom.

---

## Bezpečnostná poznámka

Skript najprv **otestuje** prihlásenie cez nového používateľa **PRED** zablokovaním roota. Ak test zlyhá, root zostane aktívny a skript skončí s varovaním — nezostaneš bez prístupu na VPS.
