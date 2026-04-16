# Skill: Debug a Analýza Logov

## Čo to je
**Systematický postup** na nájdenie príčiny problému na serveri.

## Kedy použiť
Keď aplikácia **nebeží správne**, **padá**, alebo sa **správa neočakávane**.

## Postup
1. Skontroluj či service beží: `systemctl status nazov-app`
2. Pozri **posledné logy**: `journalctl -u nazov-app -n 50`
3. Pozri logy od posledného reštartu: `journalctl -u nazov-app -b`
4. Hľadaj `ERROR`/`FATAL`/`panic`: `journalctl -u nazov-app | grep -i "error\|fatal\|panic"`
5. Skontroluj **systémové zdroje**: `free -h && df -h && top -bn1`
6. Skontroluj sieťové spojenia: `ss -tlnp`
7. Skontroluj firewall: `ufw status`

## Dôležité pravidlá
- **Vždy začni od logov** — 90% problémov je tam vysvetlených.
- **Nikdy nereštartuj service bez toho aby si si prečítal logy** — stratíš kontext.
- Pri analýze **nikdy nemeň kód** — najprv pochop problém.

## Časté chyby
- Problém: app padá okamžite → Riešenie: `journalctl -u app -n 100 --no-pager`
- Problém: app neodpovedá → Riešenie: `ss -tlnp | grep PORT`, skontroluj či počúva.
- Problém: disk full → Riešenie: `df -h`, `du -sh /var/log/*`, `journalctl --vacuum-size=100M`

## Príklady
```bash
journalctl -u moja-app -f
journalctl -u moja-app --since "10 minutes ago"
journalctl -u moja-app -n 100 --no-pager | grep -i error
ss -tlnp | grep 8080
df -h
```
