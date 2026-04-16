# Pravidlá pre Claude Code

## Projekt
[Doplň: krátky popis projektu v 1-2 vetách]

## Technológie
- Backend: [doplň]
- Frontend: [doplň]
- Databáza: [doplň]
- Server: [doplň]

## Pravidlá práce
- Pred každou zmenou súbor najprv prečítaj
- Nikdy nerob git push — iba commit
- Commit správy: feat/fix/refactor/docs: krátky popis
- Pri deštruktívnej akcii (mazanie, reset, drop) sa vždy opýtaj na potvrdenie
- Ak si nie si istý čo urobiť — opýtaj sa, nerob predpoklady
- Pred zápisom do TASKS.md a CHANGELOG.md vždy najprv prečítaj aktuálny obsah súboru

## Čo nesmiem nikdy
- [Doplň: napr. mazať databázu]
- [Doplň: napr. meniť .env súbory]
- [Doplň: napr. nasadzovať priamo na produkciu]

## Definícia "hotovej úlohy"

Po KAŽDEJ dokončenej úlohe bez výnimky urob toto v tomto poradí:

1. Skontroluj že kód funguje
2. Aktualizuj TASKS.md:
   - Najprv prečítaj aktuálny obsah súboru
   - Zaškrtni dokončený task: [ ] → [x]
   - Presuň ho do sekcie "Hotové"
3. Zapíš do CHANGELOG.md nový záznam:
   - Najprv prečítaj aktuálny obsah súboru
   - Pridaj na vrch zoznamu (najnovšie hore)
   - Formát: YYYY-MM-DD: krátky popis čo sa urobilo
   - Príklad: 2026-04-10: pridaný Event Bus pattern
   - Príklad: 2026-04-08: opravený mutex deadlock
4. Commitni: feat/fix/refactor: popis
5. Vypíš zhrnutie čo si urobil v 3-5 vetách

Toto nie je voliteľné — každá úloha končí týmito 5 krokmi.

## Štruktúra commitov
feat: nová funkcionalita
fix: oprava bugu
refactor: úprava kódu bez zmeny funkcie
docs: dokumentácia
chore: údržba, závislosti

## Pracovné prompty
Šablóny pre opakované úlohy nájdeš v .claude/prompts/
