# VCS Akadémia

Jednoduché skripty pre správu VPS servera a implementáciu AI nástrojov. Každý skript = jedna epizóda = jeden problém vyriešený.

Projekt je sprievodný materiál k YouTube kanálu **VCS Akadémia**, kde Peter z VirtuCyberSecurity učí začiatočníkov ako spravovať vlastný server a používať AI nástroje bez zbytočnej komplikovanosti.

---

## Ako používať

Každý skript si vieš stiahnuť a spustiť jedným príkazom v termináli:

```bash
curl -fsSL https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/setup-keylogin.sh | bash
```

Alebo si ho najprv stiahni a prečítaj:

```bash
curl -fsSL https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/setup-keylogin.sh -o setup-keylogin.sh
less setup-keylogin.sh
bash setup-keylogin.sh
```

---

## ⚠️ Varovanie

**Nikdy nespúšťaj skript ktorý si neprečítal.** Platí to pre tieto skripty aj pre čokoľvek iné z internetu. Otvor si súbor v editore alebo cez `less`, pozri sa čo robí, a až potom ho spusti.

Každý skript v tomto repe je verejný, otvorený a komentovaný — môžeš si overiť každý riadok.

---

## Epizódy

| # | Téma | Skript | Popis |
|---|------|--------|-------|
| 01 | SSH | [setup-keylogin.sh](01-ssh/setup-keylogin.sh) | Nastav prihlasovanie cez SSH kľúč a vypni heslo |

---

## O projekte

VCS Akadémia je vzdelávacia iniciatíva firmy [VirtuCyberSecurity](https://github.com/VirtuCyberSecurity). Cieľom je naučiť ľudí základy správy servera a praktické používanie AI nástrojov — bez akademickej vaty, bez zbytočnej teórie, len fungujúce riešenia.

- **YouTube:** VCS Akadémia
- **GitHub:** https://github.com/VirtuCyberSecurity/vcs-akademia
- **Web:** https://virtucybersecurity.com

Pull requesty a issues sú vítané.
