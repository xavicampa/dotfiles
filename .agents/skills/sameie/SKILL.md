---
name: sameie
description: The owners' association (sameiet) of the user's building. Load on any mention of sameie or sameiet.
---

# Sameiet — Clemenskvartalet (Bjørvika, Oslo)

The user lives in **Clemenskvartalet** (267 homes, Mad arkitekter, delivered autumn 2023, developer OSU / Hav Eiendom). All owner info, rules, and how-tos live on the sameiet website.

## Source of truth

**https://www.sameietclemenskvartalet.no/**

Always fetch the specific page before answering — content (prices, rules, contacts) changes. Use `fetch_content` on the URL.

## Local documents (authoritative — in this skill folder)

| File | What it is |
|---|---|
| `Vedtekter Eierseksjonssameiet Clemenskvartalet - sist endret 29.4.2026.pdf` | Sameiets vedtekter ("grunnlov"). 267 boligseksjoner + 7 næringsseksjoner. Amended 18.4.2024, 7.5.2025, **last amended at årsmøtet 29.4.2026**. |
| `Husordensregler Clemenskvartalet 9.3.2023.pdf` | Husordensregler for boligseksjonene, rev. 09.03.2023, 4 pages, §§ 1–13. |

Read them with `pdftotext` (ephemeral, per dev-env skill):
```bash
cd ~/.agents/skills/sameie && nix-shell -p poppler-utils --run \
  "pdftotext -layout Husordensregler*.pdf /tmp/husordensregler.txt && pdftotext -layout Vedtekter*.pdf /tmp/vedtekter.txt"
```
Note: package is `poppler-utils` (not the old `poppler_utils`).

For rules/questions, **prefer these PDFs over the website** — the website infobank is a summary and is sometimes looser than the formal documents. Cite the paragraph (§) number.

Key clauses:
- **Vedtekter § 2-2** — gjesteleilighetene are part of boligseksjonenes exclusive fellesarealer; rules of use are set by **årsmøtet** (eierseksjonsloven § 28). **Styret may set further rules** incl. booking/avbestilling, payment/depositum, renhold, ansvar for skade, and **"begrensninger i bruk"**. Seksjonseier is liable for use by husstandsmedlemmer/leietakere/gjester. Sanctions: midlertidig/permanent utestengelse from gjesteleilighet and other fellesgoder, cost recovery (ekstra renhold/reparasjon), deposit for future use — must be saklig begrunnet, forholdsmessig, and the seksjonseier heard first.
- **Vedtekter § 2-2** — takterrassene (6th, 7th, 9th floor) max occupancy from brannprosjektering: 100 persons (two escape routes) / 50 persons (one).
- **Vedtekter (vedlikehold)** — seksjonseier must keep the bruksenhet free of insects and skadedyr; sluk/avløp cleaning is the owner's duty.
- **Husordensregler § 1.1/1.2/1.4** — rules bind sameiers *and* husstandsmedlemmer, leietakere and besøkende; each sameier is responsible for compliance by their household/guests and for damage they cause.
- **Husordensregler § 10 DYREHOLD** — "Det er tillatt å holde dyr i sameiet." Pet can be demanded removed if til vesentlig sjenanse. Hund i bånd innenfor eiendommen. Balkonger not to be used as luftegård for hunder.
- **Husordensregler § 2.4** — lufting av hund på fellesarealer **not allowed at all** (stricter than the website's husdyrhold page).
- **Husordensregler § 2.1** — no smoking indoors/outdoors on fellesarealer, garasje, outside main entrances, or private balkonger.
- **Husordensregler § 4.4** — gass/el grill OK on balkong/terrasse; kullgrill and engangsgrill forbidden.
- **Husordensregler § 5** — ro og orden: special hensyn 23:00–07:00; no music with open doors/windows 23:00–07:00; DIY/håndverk weekdays 08–21, Saturday 09–16, extra hensyn Sundays/helligdager; no running/cycling/skateboards in oppganger/trapper/bodareal/garasje.

## Site map (infobank)

| Topic | Page |
|---|---|
| Heating & ventilation overview | `/infobank/varme-og-ventilasjon` |
| Ventilation filter (order + swap, "FILS" display) | `/infobank/filter-til-ventilasjonsanlegg` |
| Resident guide (Boligveilederen, incl. FDV docs) | `/infobank/boligveileder` |
| Buy/sell/rent | `/kjop-salg-leie` |
| Board announcements (Meldinger fra Styret) | `/meldinger` |
| Complaints (reklamasjoner) | `/infobank/reklamasjoner` |

Site root also lists news and other infobank entries — browse it if a topic isn't above.

## Communication channels

- **Heime app** — sameiet's resident communication platform (dialog, info, booking of shared services).
- **Rubus** — where complaints/claims (reklamasjoner) are filed.

## Key system facts (verify on the pages before relying on them)

- Two separate systems: balanced ventilation unit (fresh air circulation; ceiling unit in entrance or floor unit in cupboard; control panel on entrance wall near fuse box) and fan convectors with district heating (control panel in living room; heat level regulated centrally — no A/C).
- Ventilation: Exvent eWind units. Ceiling = **Alta**, wall/cupboard = **Salla**. Filter type is written inside the access panel.
- "FILS" on the eWind display = filter service due. Clear by pressing any key on the eWind panel for 5 s. Full clog = fault alarm.
- Filter: owner's responsibility since March 2025 (sameiet distribution ended). Recommended swap: every 6 months. 20% discount via code **«Clemenskvartalet»** at filtergiganten.no; originals from webshop.enervent.com. Subscription recommended.
- Ventilation setpoints: 15 °C min (summer), 22 °C max (winter); panel has 4 modes (2 = normal, 4 = boosted, auto-reverts to 2 after 120 min).
- A/C/heat pumps: not allowed on facade/balcony without written board approval (generally denied); internal integrated A/C possible via the board (>100 000 NOK).
- Complaints on temperature must be documented over multiple days (in-room middle logger); rules of thumb: ≥22 °C near heat source in winter, ≤26 °C over time in summer.
