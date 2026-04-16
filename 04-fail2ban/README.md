# Epizóda 04 — Fail2ban

Automaticky zablokuj útočníkov ktorí sa pokúšajú uhádnuť heslo na SSH. Fail2ban sleduje logy a po X neúspešných pokusoch zabanuje IP adresu útočníka.

---

## Čo skript urobí

1. Nainštaluje **Fail2ban** na VPS.
2. Vytvorí konfiguráciu pre SSH ochranu (`/etc/fail2ban/jail.d/vcs-ssh.conf`).
3. Nastaví počet pokusov pred banom (default: **5**).
4. Nastaví dĺžku banu (default: **1 hodina**).
5. Spustí Fail2ban a nastaví autostart pri reštarte servera.
6. Ukáže aktuálny stav a aktívne bany.

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- VPS s **Ubuntu/Debian** (Fail2ban musí byť dostupný cez `apt`).
- Odporúčané: dokončené epizódy **[01](../01-ssh/)**, **[02](../02-sudo-user/)**, **[03](../03-firewall/)**.

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/04-fail2ban/setup-fail2ban.sh
bash setup-fail2ban.sh
```

---

## Po spustení

Fail2ban beží na pozadí. Po **5 neúspešných pokusoch** = **ban na 1 hodinu** (alebo podľa hodnôt ktoré si zadal).

Pozrieť aktívne bany kedykoľvek:

```bash
ssh user@ip "sudo fail2ban-client status sshd"
```

---

## Bezpečnostná poznámka

Skript **nebanuje tvoju vlastnú IP**. Ak používaš key login (epizóda 01), Fail2ban ťa nikdy nezablokuje — key login totiž nezanecháva neúspešné pokusy o heslo. Bany dostávajú len útočníci ktorí skúšajú hádať heslá.
