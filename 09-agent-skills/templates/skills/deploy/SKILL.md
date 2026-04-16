# Skill: Deploy Workflow

## Čo to je
Štandardný **postup nasadenia aktualizácie** na server. Minimalizuje downtime a riziko broken deploy.

## Kedy použiť
Pri **každom nasadzovaní novej verzie** aplikácie na server.

## Postup
1. Skontroluj že všetky zmeny sú commitnuté: `git status`
2. **Zbuilduj novú verziu lokálne** a skontroluj že build prebehol bez chýb.
3. Skopíruj binárku/súbory na server: `scp` alebo `rsync`.
4. Na serveri: zastav starú verziu: `systemctl stop nazov-app`
5. **Nahraď starú binárku novou** (po zálohe — viď pravidlá).
6. Spusti novú verziu: `systemctl start nazov-app`
7. Skontroluj že beží: `systemctl is-active nazov-app`
8. Skontroluj logy či nie sú chyby: `journalctl -u nazov-app -n 20`
9. Ak niečo zlyhá: **obnov starú verziu** a spusti ju.

## Dôležité pravidlá
- **Vždy záloha** starej binárky pred nahradením: `cp app app.bak`
- **Nikdy nerob deploy priamo na produkciu bez testu.**
- **Zastav service PRED kopírovaním** novej binárky.
- Ak deploy zlyhá: `systemctl stop app` → `cp app.bak app` → `systemctl start app`

## Časté chyby
- Chyba: `permission denied` pri kopírovaní → Riešenie: skontroluj vlastníka súboru.
- Chyba: app sa nespustí po deploy → Riešenie: `journalctl -u app -n 50`, obnov zálohu.
- Chyba: `port already in use` → Riešenie: stará verzia stále beží, `systemctl stop`.

## Príklady
```bash
# Lokálne
go build -o app ./cmd/app

# Na server
scp app user@server:/opt/app/app.new
ssh user@server '
  cp /opt/app/app /opt/app/app.bak &&
  systemctl stop nazov-app &&
  mv /opt/app/app.new /opt/app/app &&
  systemctl start nazov-app &&
  systemctl is-active nazov-app
'
```
