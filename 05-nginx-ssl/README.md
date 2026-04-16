# Epizóda 05 — Nginx + SSL

Nainštaluj webový server a získaj bezplatný HTTPS certifikát. Po tejto epizóde môžeš sprístupniť akúkoľvek aplikáciu cez doménu s HTTPS.

---

## Čo skript urobí

1. Nainštaluje **Nginx** a **Certbot** na VPS.
2. Vytvorí server block pre tvoju doménu (`/etc/nginx/sites-available/`).
3. Otestuje Nginx konfiguráciu (`nginx -t`).
4. Získa SSL certifikát od **Let's Encrypt** (zdarma, platný 90 dní).
5. Nastaví automatické presmerovanie **HTTP → HTTPS**.
6. Nastaví automatické obnovovanie certifikátu (cez `certbot.timer`).
7. Otestuje že HTTPS funguje a vráti správny HTTP kód.

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- VPS s **Ubuntu/Debian** (Nginx a Certbot dostupné cez `apt`).
- **Doména** ktorá smeruje na IP tvojho VPS (A record nastavený u registrátora).
- Otvorené porty **80** a **443** na firewalle (epizóda **[03](../03-firewall/)** — UFW).
- Odporúčané: dokončené epizódy **[01](../01-ssh/)**, **[02](../02-sudo-user/)**, **[03](../03-firewall/)**, **[04](../04-fail2ban/)**.

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/05-nginx-ssl/setup-nginx-ssl.sh
bash setup-nginx-ssl.sh
```

---

## Po spustení

Tvoj web beží na `https://tvoja-domena.sk` s platným SSL certifikátom. Certifikát sa **obnovuje automaticky** každých 90 dní — netreba sa o nič starať.

Pridať novú aplikáciu (napr. ďalšiu doménu alebo subdoménu): vytvor nový server block v `/etc/nginx/sites-available/`, vytvor symlink do `/etc/nginx/sites-enabled/` a spusti znova `certbot --nginx -d nova-domena.sk`.

---

## Bezpečnostná poznámka

**Let's Encrypt vyžaduje, aby doména skutočne smerovala na IP tvojho VPS PRED spustením skriptu.** Skript túto skutočnosť overí (porovná DNS záznam s verejnou IP servera) a varuje ťa, ak niečo nesedí.

Ak DNS ešte nestihlo propagovať, počkaj 10–60 minút a spusti skript znova. Let's Encrypt má **rate limit 5 certifikátov za týždeň pre jednu doménu**, takže neskúšaj donekonečna.
