# Epizóda 07 — Tmux

Spusti **Claude Code** (alebo čokoľvek iné) na VPS tak, aby bežalo **aj po zatvorení terminálu**. Tmux udržuje session nažive — pripojíš sa kedykoľvek späť presne tam, kde si skončil.

---

## Čo skript urobí

1. Nainštaluje **tmux** na VPS.
2. Vytvorí **tmux konfiguráciu** (väčšia história, mouse mode, lepšie farby).
3. Vytvorí **named session** `claude` (alebo iný názov podľa tvojej voľby).
4. Voliteľne **spustí Claude Code** v session.
5. Ukáže ako sa **pripojiť späť** po odpojení.

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- VPS s **Ubuntu/Debian**.
- Odporúčané: dokončená epizóda **[06](../06-claude-code/)** (Claude Code).

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/07-tmux/setup-tmux.sh
bash setup-tmux.sh
```

---

## Základné príkazy po inštalácii

| Akcia                           | Príkaz / klávesa                  |
|---------------------------------|-----------------------------------|
| Pripojiť sa k session           | `tmux attach -t claude`           |
| Odpojiť sa (session beží ďalej) | `Ctrl+B` potom `D`                |
| Zoznam všetkých sessions        | `tmux ls`                         |
| Vytvoriť novú session           | `tmux new -s nazov`               |
| Zabiť session                   | `tmux kill-session -t claude`     |
| Reload konfigurácie (v tmuxe)   | `Ctrl+B` potom `R`                |

---

## Bezpečnostná poznámka

Tmux session beží **ako tvoj user**. Čokoľvek čo spustíš vnútri (Claude Code, dlhé buildy, skripty) má **rovnaké práva ako ty** — preto session **nespúšťaj ako root**, ak to nie je nevyhnutné. Použi sudo usera z [epizódy 02](../02-sudo-user/).
