# Skill: Docker

## Čo to je
Docker spúšťa aplikácie v izolovaných **kontajneroch**. Každá aplikácia má vlastné prostredie — žiadne konflikty závislostí medzi projektami.

## Kedy použiť
Pri buildovaní, spúšťaní alebo deployovaní kontajnerizovaných aplikácií.

## Postup — build a spustenie
1. Skontroluj že `Dockerfile` existuje v root adresári projektu.
2. Zbuilduj image: `docker build -t nazov-projektu:latest .`
3. Spusti kontajner: `docker run -d --name nazov-projektu -p HOST_PORT:CONTAINER_PORT nazov-projektu:latest`
4. Skontroluj že beží: `docker ps`
5. Skontroluj logy: `docker logs nazov-projektu`

## Postup — zastavenie a aktualizácia
1. Zastav kontajner: `docker stop nazov-projektu`
2. Zmaž starý kontajner: `docker rm nazov-projektu`
3. Zbuilduj nový image (krok 2 vyššie).
4. Spusti nový kontajner (krok 3 vyššie).

## Dôležité pravidlá
- **Vždy použi `--name`** pri `docker run` — ľahšie spravovanie.
- **Nikdy nespúšťaj kontajner ako root** ak to nie je nevyhnutné.
- **Vždy bind na `127.0.0.1`** ak kontajner nie je verejný: `-p 127.0.0.1:PORT:PORT`.
- Pri aktualizácii **najprv zastav** starý kontajner pred buildovaním nového.

## Časté chyby
- Chyba: `port already in use` → Riešenie: `docker stop $(docker ps -q --filter publish=PORT)`
- Chyba: `no space left on device` → Riešenie: `docker system prune -f`
- Chyba: kontajner sa okamžite zastaví → Riešenie: `docker logs nazov-projektu`

## Príklady
```bash
docker build -t moja-app:latest .
docker run -d --name moja-app -p 127.0.0.1:8080:8080 moja-app:latest
docker logs -f moja-app
docker exec -it moja-app /bin/bash
```
