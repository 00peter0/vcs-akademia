# Skill: Systemd Service

## Čo to je
Systemd spravuje **služby na Linuxe** — spúšťa ich pri štarte, reštartuje pri páde, zbiera logy cez `journalctl`.

## Kedy použiť
Pri nasadzovaní akejkoľvek aplikácie ktorá má **bežať nepretržite** na serveri.

## Postup — vytvorenie service
1. Vytvor súbor: `/etc/systemd/system/nazov-app.service`
2. Načítaj zmeny: `systemctl daemon-reload`
3. Zapni autostart: `systemctl enable nazov-app`
4. Spusti: `systemctl start nazov-app`
5. Skontroluj: `systemctl status nazov-app`

## Service šablóna
```ini
[Unit]
Description=Popis aplikácie
After=network.target

[Service]
Type=simple
User=LINUX_USER
WorkingDirectory=/cesta/k/projektu
ExecStart=/cesta/k/binarke --flagy
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

## Dôležité pravidlá
- **Vždy spusti `systemctl daemon-reload`** po zmene `.service` súboru.
- **Nikdy nespúšťaj produkčné služby ako root** — použi dedikovaného usera.
- `Restart=on-failure` reštartuje **pri páde** ale nie pri `systemctl stop`.
- `WorkingDirectory` musí **existovať** pred spustením.

## Časté chyby
- Chyba: service sa nespustí → Riešenie: `journalctl -u nazov-app -n 50`
- Chyba: `permission denied` → Riešenie: skontroluj `User=` a práva na súbory.
- Chyba: `exec format error` → Riešenie: binárka nie je pre správnu architektúru.

## Príklady
```bash
systemctl status nazov-app
systemctl restart nazov-app
journalctl -u nazov-app -f
journalctl -u nazov-app --since "1 hour ago"
```
