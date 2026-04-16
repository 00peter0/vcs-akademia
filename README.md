# VCS Akadémia

Jednoduché skripty pre správu VPS servera a implementáciu AI nástrojov. Každý skript = jedna epizóda = jeden problém vyriešený.

Projekt je sprievodný materiál k YouTube kanálu **VCS Akadémia**, kde Peter z VirtuCyberSecurity učí začiatočníkov ako spravovať vlastný server a používať AI nástroje bez zbytočnej komplikovanosti.

---

## Ako používať

Každý skript si stiahneš a spustíš dvomi príkazmi v termináli:

```bash
curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/setup-keylogin.sh
bash setup-keylogin.sh
```

**Windows používatelia:** potrebujete [Git Bash](https://gitforwindows.org). Všetky skripty bežia v Git Bash rovnako ako v Mac/Linux termináli.

**Mac/Linux:** funguje rovno v termináli, žiadna inštalácia nie je potrebná.

---

## Varovanie

**Nikdy nespúšťaj skript ktorý si neprečítal.** Platí to pre tieto skripty aj pre čokoľvek iné z internetu. Každý skript v tomto repe je krátky, verejný a komentovaný — otvor si ho pred spustením v editore alebo cez `less` a pozri sa čo robí.

---

## Epizódy

| #  | Téma                                            | Skript     | Video   |
|----|-------------------------------------------------|------------|---------|
| 01 | SSH Key Login — prihlásenie bez hesla           | [01-ssh/](01-ssh/) | čoskoro |
| 02 | Sudo User + Zakáž Root Login                    | [02-sudo-user/](02-sudo-user/) | čoskoro |
| 03 | UFW Firewall                                    | [03-firewall/](03-firewall/) | čoskoro |
| 04 | Fail2ban — automatický ban brute-force útokov   | [04-fail2ban/](04-fail2ban/) | čoskoro |
| 05 | Nginx + SSL — web server s HTTPS                | [05-nginx-ssl/](05-nginx-ssl/) | čoskoro |
| 06 | Claude Code Agent — AI na VPS                   | [06-claude-code/](06-claude-code/) | čoskoro |
| 07 | Tmux — session manager pre Claude Code          | [07-tmux/](07-tmux/) | čoskoro |
| 08 | Agent Setup — CLAUDE.md, PROJECT.md, TASKS.md   | [08-agent-setup/](08-agent-setup/) | čoskoro |

---

## O projekte

VCS Akadémia je vzdelávacia iniciatíva firmy [VirtuCyberSecurity](https://github.com/VirtuCyberSecurity). Cieľom je naučiť ľudí základy správy servera a praktické používanie AI nástrojov — bez akademickej vaty, len fungujúce riešenia.

- **YouTube:** VCS Akadémia
- **GitHub:** https://github.com/VirtuCyberSecurity/vcs-akademia

Pull requesty a issues sú vítané.
# vcs-akademia
