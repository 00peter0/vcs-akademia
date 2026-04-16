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
