# Epizóda 09 — Agent Skills

**Skills** sú návody pre agenta — *ako urobiť konkrétnu vec správne*. Bez skillu agent **vymýšľa** (a často sa pomýli). So skillom vie **presne čo robiť**, lebo si prečíta tvoj návod skôr než začne pracovať.

---

## Čo je skill

Skill je **markdown súbor** ktorý agent prečíta **pred tým ako začne úlohu**.

Obsahuje:

- **Čo nástroj/workflow robí** — krátko, jednou-dvomi vetami.
- **Ako ho použiť** — číslovaný postup, presné príkazy.
- **Úskalia a časté chyby** — čo sa typicky pokazí a ako to riešiť.
- **Príklady** — konkrétne príkazy na skopírovanie.

Agent si skill prečíta sám — buď keď mu **povieš kde je** v prompte, alebo **automaticky** ak to máš zapísané v `CLAUDE.md`.

---

## Typy skills

| Typ | Príklad | Kedy použiť |
|------|---------|-------------|
| **Nástroj skill** | docker, nginx, systemd | Ako použiť konkrétny nástroj. |
| **Workflow skill** | deploy, debug, backup | Ako urobiť opakujúcu sa úlohu krok po kroku. |
| **Projekt skill** | kód-konvencie, naming, branch-flow | Pravidlá špecifické pre **tvoj** projekt. |

---

## Štruktúra skills v projekte

```
projekt/
├── CLAUDE.md
├── PROJECT.md
├── TASKS.md
├── CHANGELOG.md
└── .claude/
    ├── prompts/
    └── skills/
        ├── docker/SKILL.md
        ├── nginx/SKILL.md
        └── deploy/SKILL.md
```

Každý skill má **vlastný adresár** so súborom `SKILL.md`. Adresár môže obsahovať aj pomocné súbory (príklady configov, šablóny), ale `SKILL.md` je **vždy hlavný vstupný bod**.

---

## Ako agent použije skill

**Možnosť 1 — manuálne v prompte:**

```
Použi .claude/skills/docker/SKILL.md a vytvor Dockerfile pre Go aplikáciu.
```

**Možnosť 2 — automaticky cez `CLAUDE.md`:**

Pridaj do `CLAUDE.md`:

```markdown
## Skills
Pred prácou s týmito nástrojmi vždy prečítaj príslušný skill:
- docker: .claude/skills/docker/SKILL.md
- nginx:  .claude/skills/nginx/SKILL.md
- deploy: .claude/skills/deploy/SKILL.md
```

Tým pádom agent vie kedy a ktorý skill má siahnuť. **Skript ti to nastaví automaticky.**

---

## Čo skript urobí

1. Skopíruje **šablónu `SKILL.md`** do projektu (aby si vedel písať vlastné skills).
2. Skopíruje **hotové skills** ktoré si vyberieš (docker, nginx, systemd, deploy, debug).
3. **Aktualizuje `CLAUDE.md`** — pridá sekciu *Skills* aby agent vedel kde ich má hľadať.

---

## Požiadavky

- **Mac / Linux:** terminál (všetko je predinštalované).
- **Windows:** [Git Bash](https://gitforwindows.org).
- Existujúci projekt s **`CLAUDE.md`** (odporúčame najprv prejsť epizódou **[08](../08-agent-setup/)**).

---

## Spustenie

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/09-agent-skills/setup-skills.sh
bash setup-skills.sh
```

---

## Ako napísať vlastný skill

Použi šablónu, ktorú ti skript skopíruje do projektu:

```
.claude/skills/SKILL-TEMPLATE.md
```

**Dobré pravidlá pre skill:**

- **Buď konkrétny.** Žiadne *„možno"*, *„závisí"* alebo *„skús niečo"*. Agent potrebuje rozhodnutia, nie návrhy.
- **Uveď úskalia a časté chyby.** To je často to **najcennejšie** — agent sa nimi vyhne na prvý pokus.
- **Pridaj príklady príkazov.** Skopírovateľné, hotové, otestované.
- **Krátko a jasne.** Agent **číta celý súbor** — každé slovo navyše ho len rozptyľuje.

---

## Bezpečnostná poznámka

Skills idú **do tvojho repa**. Nepíš do nich heslá, tokeny ani interné URL produkčného serveru. Na to je `.env` (a ten **nikdy** necommituj). Skills majú obsahovať **postupy**, nie **secrets**.
