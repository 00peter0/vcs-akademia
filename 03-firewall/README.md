# Epizóda 03 — UFW Firewall

Nastav firewall na VPS. Zakáž všetko čo nepotrebuješ, povol len SSH a tvoje služby. Jeden z najdôležitejších krokov po inštalácii servera.

---

## Čo skript urobí

1. Opýta sa na SSH port a ďalšie porty ktoré chceš otvoriť.
2. Zakáže všetky prichádzajúce spojenia.
3. Povolí odchádzajúce spojenia.
4. Povolí tvoj SSH port (**pred** zapnutím UFW).
5. Povolí ďalšie porty ktoré zadáš (napr. `80`, `443`, custom).
6. Zapne UFW.
7. Otestuje že SSH stále funguje.
8. Zobrazí aktívne pravidlá.

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- VPS s **Ubuntu/Debian** (UFW musí byť dostupný cez `apt`).
- Odporúčané: dokončená **[Epizóda 01](../01-ssh/)** — SSH key login.

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/03-firewall/setup-ufw.sh
bash setup-ufw.sh
```

---

## Po spustení

Firewall je aktívny. Otvorené sú len porty ktoré si zadal — všetko ostatné je zablokované.

---

## Bezpečnostná poznámka

Skript povolí SSH port **PRED** zapnutím UFW. Ak by sa aj niečo pokazilo, máš vždy prístup cez **emergency konzolu** tvojho VPS providera (Hetzner, Contabo, DigitalOcean, OVH…) — odtiaľ vieš firewall vypnúť príkazom `ufw disable`.
