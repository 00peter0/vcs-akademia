# Skill: Nginx Reverse Proxy

## Čo to je
Nginx prijíma HTTP/HTTPS požiadavky a **preposiela ich na aplikáciu** bežiacu lokálne. Aplikácia beží na porte 8080, Nginx ju sprístupní cez doménu s HTTPS.

## Kedy použiť
Pri sprístupnení akejkoľvek aplikácie cez doménu s HTTPS.

## Postup — nový reverse proxy
1. Skontroluj či Nginx beží: `systemctl is-active nginx`
2. Vytvor config súbor: `/etc/nginx/sites-available/DOMENA`
3. Vytvor symlink: `ln -sf /etc/nginx/sites-available/DOMENA /etc/nginx/sites-enabled/`
4. Otestuj config: `nginx -t`
5. Reload: `systemctl reload nginx`
6. Ak nemáš SSL: `certbot --nginx -d DOMENA --non-interactive --agree-tos --email EMAIL --redirect`

## Config šablóna (HTTP → aplikácia na porte 8080)
```nginx
server {
    listen 80;
    server_name DOMENA;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Dôležité pravidlá
- **Vždy spusti `nginx -t` pred reloadom** — nikdy nenačítaj broken config.
- Aplikácia musí byť **bindnutá na `127.0.0.1`** nie `0.0.0.0`.
- **Jeden server block = jedna doména.**
- **Nikdy nemeň `/etc/nginx/nginx.conf`** — len `sites-available/`.

## Časté chyby
- Chyba: `nginx -t` zlyhá → Riešenie: skontroluj syntax, chýbajúce bodkočiarky alebo zátvorky.
- Chyba: `502 Bad Gateway` → Riešenie: aplikácia nebeží alebo beží na inom porte.
- Chyba: `certbot` zlyhá → Riešenie: port 80 musí byť otvorený a doména musí smerovať na server.

## Príklady
```bash
nginx -t
systemctl reload nginx
certbot --nginx -d example.com --non-interactive --agree-tos --email me@example.com --redirect
tail -f /var/log/nginx/error.log
```
