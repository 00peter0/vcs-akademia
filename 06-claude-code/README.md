# Epizóda 06 — Claude Code Agent

Nainštaluj **Claude Code** na VPS a spusti AI agenta priamo na serveri. Funguje s **Claude.ai Max** predplatným aj s **Anthropic API kľúčom**.

---

## Čo skript urobí

1. Nainštaluje **Node.js** (LTS) cez oficiálny NodeSource repozitár.
2. Nainštaluje **Claude Code CLI** (`@anthropic-ai/claude-code`) cez `npm`.
3. Overí inštaláciu (`claude --version`).
4. Spustí prihlásenie — **ty si vyberieš** subscription (Claude.ai Max) alebo API key.
5. Voliteľne vytvorí **projekt folder** s `CLAUDE.md` (pravidlá pre agenta).

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- VPS s **Ubuntu/Debian**.
- **Claude.ai Max** predplatné **ALEBO** Anthropic **API kľúč** (https://console.anthropic.com/).
- Odporúčané: dokončené epizódy **[01](../01-ssh/)** (SSH key) a **[02](../02-sudo-user/)** (sudo user).

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/06-claude-code/setup-claude-code.sh
bash setup-claude-code.sh
```

---

## Po spustení

Pripoj sa na VPS a používaj agenta:

```bash
ssh user@ip
claude                  # spusti Claude Code v aktuálnom adresári
claude --version        # skontroluj verziu
claude auth logout      # odhlás sa
```

---

## Poznámka

Claude Code beží **interaktívne v termináli** — potrebuješ aktívne SSH spojenie. Keď zatvoríš terminál, agent sa ukončí.

Ak chceš nechať agenta bežať aj po zatvorení SSH (napr. dlhá refaktorizácia, nočná analýza), pozri **epizódu 07 — tmux**, ktorá rieši perzistentné session.
