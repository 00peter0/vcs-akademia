# Epizóda 08 — Nastavenie Claude Code Agenta

Pred každým projektom vytvor tieto súbory — agent bude vedieť **kto je, čo robí, čo smie a čo nie**. Bez nich sa agent stráca, robí predpoklady a skončíš s kódom ktorý si nechcel.

---

## Prečo tieto súbory

| Súbor | Na čo je |
|------|----------|
| **CLAUDE.md** | Pravidlá, štýl, čo agent smie a čo nesmie. |
| **PROJECT.md** | Čo projekt je, stack, architektúra, ako sa spúšťa a deployuje. |
| **TASKS.md** | Čo sa robí teraz, čo je hotové, čo čaká. |
| **CHANGELOG.md** | Čo sa zmenilo a kedy. |
| **.claude/prompts/** | Šablóny pre opakované úlohy (nová feature, fix bugu, review, deploy). |

---

## Čo skript urobí

1. Opýta sa na základné info o projekte (cesta, názov, popis, stack).
2. Skopíruje šablóny (`CLAUDE.md`, `PROJECT.md`, `TASKS.md`, `CHANGELOG.md` + prompty) do tvojho projektu.
3. Vyplní základné info ktoré si zadal.
4. Vypíše čo treba doplniť manuálne.

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- Existujúci project folder (alebo nový — skript sa opýta či ho vytvoriť).
- Odporúčané: dokončená epizóda **[06](../06-claude-code/)** (Claude Code).

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/08-agent-setup/setup-agent.sh
bash setup-agent.sh
```

---

## Po spustení

Otvor každý súbor a **doplň detaily špecifické pre tvoj projekt**. Čím viac kontextu dáš, tým lepšie agent pracuje.

Minimum čo treba doplniť manuálne:

- `CLAUDE.md` → sekcia **Čo nesmiem nikdy** (napr. "nemazať databázu", "nedotýkať sa .env").
- `PROJECT.md` → **štruktúra projektu**, **ako spustiť lokálne**, **ako deploynúť**.
- `TASKS.md` → prvé úlohy projektu.
- `.claude/prompts/deploy.md` → presný postup deployu.

---

## Ako agent používa tieto súbory

- **CLAUDE.md a PROJECT.md** — agent ich číta **pri každej úlohe**, aby vedel pravidlá a kontext.
- **TASKS.md** — agent ho **aktualizuje po každej dokončenej úlohe**.
- **CHANGELOG.md** — agent ho **aktualizuje po každom commite**.
- **.claude/prompts/** — šablóny **použiješ ty**, keď zadávaš opakujúce sa úlohy (stačí povedať "použi prompt new-feature pre...").

---

## Bezpečnostná poznámka

Tieto súbory obsahujú **popis tvojho projektu** — stack, architektúru, deploy postup. Ak commitneš repo verejne, **nepíš do nich heslá, tokeny ani citlivé URL**. Na to je `.env` (a ten **nikdy** necommituj).
