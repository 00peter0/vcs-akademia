# Epizóda 01 — SSH Key Login

Tento skript nastaví bezpečné prihlasovanie na tvoj VPS server pomocou SSH kľúča a vypne prihlasovanie heslom. Po dokončení sa už nikto nemôže prihlásiť cez heslo — iba s tvojim privátnym kľúčom.

---

## Čo skript urobí

1. **Vygeneruje SSH keypair** (`ed25519`) v `~/.ssh/id_ed25519`, ak ešte neexistuje.
2. **Skopíruje verejný kľúč** na VPS pomocou `ssh-copy-id` (toto je posledný raz, kedy zadáš heslo).
3. **Otestuje prihlásenie cez kľúč**, aby sa overilo, že to funguje.
4. **Upraví `/etc/ssh/sshd_config`** na VPS — vypne `PasswordAuthentication`, zapne `PubkeyAuthentication`.
5. **Reštartuje SSH službu** na VPS (podporuje `systemctl` aj `service`).
6. **Overí key login ešte raz** po reštarte — ak zlyhá, varuje a NEROBÍ rollback automaticky.

---

## Požiadavky

- Lokálny počítač s terminálom:
  - **macOS** alebo **Linux** — funguje out-of-the-box
  - **Windows** — použi **Git Bash** alebo **WSL**
- VPS s aktívnym SSH prístupom (musíš poznať IP, username a heslo)
- Nástroje `ssh`, `ssh-keygen`, `ssh-copy-id` (štandardná súčasť OpenSSH)

---

## Použitie

Stiahni a spusti jedným príkazom:

```bash
curl -fsSL https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/setup-keylogin.sh | bash
```

Alebo bezpečnejšie — najprv si skript prečítaj:

```bash
curl -fsSL https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/setup-keylogin.sh -o setup-keylogin.sh
less setup-keylogin.sh
bash setup-keylogin.sh
```

---

## Čo sa stane po spustení

Skript sa ťa interaktívne opýta na:

- **IP adresu VPS** (napr. `51.89.42.38`)
- **Username** (default: `root`)
- **SSH port** (default: `22`)

Potom prejde všetkými krokmi a ku každému ti vypíše farebný status. Heslo na VPS zadáš iba raz — pri kopírovaní kľúča.

Na konci dostaneš presný príkaz na prihlásenie, napr.:

```bash
ssh -i ~/.ssh/id_ed25519 root@51.89.42.38
```

---

## ⚠️ Bezpečnostná poznámka

**Po dokončení tohto skriptu je heslo natrvalo vypnuté.** Na VPS sa dostaneš LEN s privátnym kľúčom (`~/.ssh/id_ed25519`).

To znamená:

- **Zazálohuj si privátny kľúč** na bezpečné miesto (USB, password manager). Ak ho stratíš, stratíš prístup na server.
- Ak si poskytovateľ VPS (Hetzner, OVH, atď.) ponúka **rescue mode** alebo **konzolu cez webové rozhranie**, vieš sa dostať na server aj bez SSH — ale je to oveľa nepríjemnejšie.
- Skript NEROBÍ automatický rollback ak test po reštarte zlyhá. To je zámer — necháva ťa rozhodnúť, či chceš debugovať alebo vrátiť zmeny manuálne.
