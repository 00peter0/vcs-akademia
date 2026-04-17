# Epizóda 01 — SSH Key Login

Nastav prihlásenie na VPS bez hesla. Bezpečnejšie, pohodlnejšie. Heslo zadáš len raz — potom nikdy viac.

---

## Čo skript urobí

1. Skontroluje či máš SSH key — ak nie, vygeneruje ho.
2. Skopíruje tvoj verejný key na VPS (tu zadáš heslo naposledy).
3. Vypne prihlásenie heslom na VPS.
4. Otestuje či key login funguje.
5. Zobrazí príkaz na prihlásenie.

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- VPS s aktívnym SSH prístupom a heslom (musíš poznať IP, username a heslo).

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/setup-keylogin.sh
bash setup-keylogin.sh
```

---

## Po spustení

Prihlásenie bez hesla:

```bash
ssh user@ip
```

Heslo na VPS už nefunguje — prihlásiť sa vieš iba s privátnym kľúčom (`~/.ssh/id_ed25519`).

---

## Bezpečnostná poznámka

Zálohu privátneho kľúča drž na bezpečnom mieste (`~/.ssh/id_ed25519`). Ak ho stratíš, budeš potrebovať prístup cez konzolu VPS providera (rescue mode, web konzola).

---

# Epizóda 01a — Záloha SSH kľúča na USB

Po nastavení key loginu je dôležité zálohovať privátny kľúč. Ak ho stratíš, stratíš prístup na server.

---

## Čo skript urobí

1. Skontroluje či máš SSH kľúč (`~/.ssh/id_ed25519`).
2. Detekuje pripojené USB zariadenia (Mac / Linux / Windows Git Bash).
3. Nechá ťa vybrať USB zariadenie.
4. Skopíruje privátny aj verejný kľúč na USB.
5. Nastaví správne práva na súboroch.
6. Vytvorí README.txt s návodom na obnovu.
7. Overí, že záloha nie je poškodená.

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- Pripojené USB zariadenie.
- Existujúci SSH kľúč (najprv spusti epizódu 01).

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/backup-ssh-key.sh
bash backup-ssh-key.sh
```

---

## Po spustení

Na USB nájdeš adresár `vcs-akademia-ssh-backup/YYYY-MM-DD/` s troma súbormi:

- `id_ed25519` — privátny kľúč
- `id_ed25519.pub` — verejný kľúč
- `README.txt` — návod na obnovu

---

## Bezpečnostná poznámka

USB drž na bezpečnom mieste, oddelene od počítača. Privátny kľúč (`id_ed25519`) nikdy nezdieľaj.
