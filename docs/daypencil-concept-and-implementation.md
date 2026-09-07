# Daypencil — Concept and Implementation Plan

Selected name · Implementation brief · 7 September 2026

**Domain.** `daypencil.com` — showed available for registration at $11.08/year on Porkbun when checked on 7 September 2026. The domain has not been registered as part of this work.

**Product.** Daypencil is a free daily puzzle paper for phones and the web. It combines familiar daily games with a short playable edition about interesting things happening in the world. Players can open their favourite game immediately, discover three current stories, or settle in for a longer session.

The promise is a satisfying daily ritual: familiar puzzles, a few worthwhile discoveries, and results that are easy to share. The news edition takes about three to five minutes. The classics remain available independently throughout the day.

The first release includes all four core classics, the three news games, the Front Page, an archive, local progress, offline support after download, sharing, and optional donations. Build the web version as an installable phone experience, then package the same product for iOS and Android.

**Planning defaults.** Start with English and a UK-oriented editorial selection. These are implementation assumptions, not inferred user preferences. Use one shared edition boundary at 04:00 UTC and explicit edition dates everywhere. Keep language, spelling conventions, dictionary and editorial market in configuration so a later market can use the same engines.

## The daily games

| Component | Rules and experience | Content and implementation |
|---|---|---|
| **Mini Crossword** | One compact 5×5 crossword each day. Tap a clue or cell, switch across/down, use the keyboard, and resume later. Hints and reveals are available and recorded in the result. | Generate grids ahead from a checked clue-and-answer collection. Verify crossings, numbering, spelling, fill and clue assignment. Keep enough variety that common answers and clues do not recur frequently. |
| **Bee-style Letters** | Seven letters, including a compulsory centre letter. Form words of at least four letters; letters can repeat. Four-letter words earn one point; longer words earn their length; a word using all seven letters earns a seven-point bonus. | Use a versioned accepted-word dictionary. Select letter sets with at least one pangram, a manageable answer count and a useful spread of common words. Freeze the answer set and maximum score for every dated puzzle. |
| **Daily Word — Motus-style** | Find a six-letter word in six guesses, with the first letter supplied. Feedback identifies correctly placed letters, misplaced letters and absent letters. | Use a curated answer list and a broader list of valid guesses. Implement repeated-letter feedback by consuming exact matches before allocating misplaced matches. Keep rules and word length consistent. |
| **Sudoku** | One daily puzzle in each of three difficulties. Include notes, undo, optional mistake checking and save/resume. Timing is optional on screen. | Generate and solve puzzles ahead. Verify exactly one solution and classify difficulty using required solving techniques. Difficulty is part of the puzzle identity and shared result. |
| **Correct** | A short headline or dispatch contains one deliberately altered detail. Two small evidence cards give the information needed to identify the error and choose its repair. Allow three attempts. | Build from structured source facts. Use constrained changes to numbers, dates, units or comparisons, with a finite set of answer options. Check that exactly one option satisfies the supplied evidence. Clearly label the dispatch as a puzzle containing an alteration. |
| **The Number** | Estimate a figure from a different current story using a slider and optional numeric input. A comparison gives a useful reference point. Show the real figure, its context and the distance from the estimate. | Store the entity, measurement, unit, period, source passage and answer together. Define range and scoring scale in the puzzle data. Avoid facts already revealed in another game. |
| **Where** | Use two short clues to locate the setting of a third story on a map. Show distance and a short explanation after the guess. Provide a keyboard-accessible location-selection alternative. | Use verified place records and coordinates. Set an appropriate acceptance radius or area, so a regional answer is not judged against an arbitrary exact point. Publish only when the clues narrow the location meaningfully. |
| **Front Page** | The three stories form a clean newspaper-style card as the player completes the news games. Each story has a concise explanation and source link. The completed page provides a clear ending. | Generate the recap from the same approved facts used in the games. Show completed stories immediately; let the player explicitly reveal any unplayed stories when choosing to finish early. |

The original evidence-and-repair mechanic gives the news edition a clear editing action. The four classic games provide familiar daily destinations. Each news game covers a different story, preventing one reveal from giving away the next answer.

## The experience

The home page shows today's edition date, the news edition and the four classic games. Every game is one tap away. Players can pin favourites, see which games they have started, and resume an unfinished puzzle.

The news edition presents Correct, The Number and Where in that order, followed by the Front Page. Players can leave after any round and open their completed story cards. The app never requires finishing the classics to complete the news edition.

Each game uses the same navigation, save behaviour, help pattern and result screen. Explain a rule through a short example on first use, then leave help accessible. Use individual game statistics and optional streaks, with a neutral calendar history that also works for occasional players.

The visual direction is a small, well-designed newspaper: generous spacing, strong typography, a warm light theme, a comfortable dark theme, restrained colour and brief transitions. Colour feedback also uses symbols or labels. Support reduced motion, readable text sizes and comfortable touch targets.

A free archive preserves earlier puzzles through the same links used for sharing. Archive play is labelled with its original date and recorded separately from completion of the current edition.

## Sharing and playing the same puzzle

Every puzzle receives a permanent identity containing its game, edition date, language, difficulty where relevant, and version. A shared link always opens that exact puzzle, including when received later.

Build two actions into every result screen:

- **Share result:** a spoiler-free text card and optional image containing the game, date and relevant result. Use attempts for Daily Word and Correct, points for Letters, optional time and hints for Crossword and Sudoku, and distance for the estimation and map games.
- **Challenge a friend:** the same puzzle link with an optional compact result to beat. The recipient can play immediately on the web. Only the score summary travels in the link; answers, full move history and personal identifiers do not.

Use a native share sheet when supported, with Copy Link, Copy Result and Download Image fallbacks. Web Share requires HTTPS and has uneven browser support, so those fallbacks are part of the implementation. [MDN Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API).

Generate result images on the player's device. Prepare neutral preview images for puzzle links during publishing. Keep a readable text equivalent for accessibility and messaging apps.

The web and phone apps load the same published puzzle data and scoring rules. Challenge results are friendly comparisons, stored locally, without a central competitive ranking. This delivers online play and score sharing without player accounts.

## Content production

**Classic games.** Build a reusable content collection during development. Start with at least 90 prepared daily sets, including all three Sudoku difficulties. Maintain a rolling reserve through batch generation.

Sudoku uses a generator and solver. Daily Word uses a curated common-word answer schedule. Letters uses dictionary searches and repeatable quality rules. Crossword uses a checked clue-and-answer bank and a grid generator; new clue records receive content review before entering that bank. Grid generation alone is not treated as verification of clue quality.

Document the word policy in the product: permitted spellings and inflections, treatment of proper nouns, abbreviations, hyphens and apostrophes. Store dictionary versions with puzzles so a later vocabulary change does not silently change an older puzzle's score.

**News edition.** Select current stories from a small allowlist of sources covering science, culture, technology, nature, discoveries and everyday life. Apply the existing exclusions for war, violent crime, disasters and partisan politics. Describe the result as a selection of interesting current stories.

During implementation, configure three to five source adapters. Record what each source permits the product to retrieve, retain and display. Each story record contains its publisher, URL, publication time, relevant excerpts, structured facts and any qualifiers. Keep original article links available after the reveal.

Use attributed factual summaries rather than claims of complete news coverage. For example, the Guardian distinguishes non-commercial developer access from commercial access; source arrangements therefore belong in setup and budgeting. [Guardian Open Platform](https://open-platform.theguardian.com/access/).

## Daily publishing

Run the publisher at 02:17 UTC, ahead of the 04:00 UTC edition opening. Use a second scheduled check before the deadline to retry a failed run or confirm the prepared fallback. Cloudflare Cron Triggers use UTC scheduling. [Cloudflare Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/).

The publisher follows this sequence:

1. Retrieve eligible source material and remove duplicate or recently reused stories.
2. Extract structured facts and source passages, retaining units, dates, entities, locations and qualifiers.
3. Choose three stories that fit the fixed news games. Prefer a different topic for each round.
4. Request structured JSON for puzzle text, permitted answer options and the recap. Keep game code, scoring and rule enforcement outside the model.
5. Run schema checks, source checks, answer checks and checks for answers leaked by another game's wording or reveal.
6. Reject ambiguous candidates and use a bounded number of alternative candidates or model retries.
7. Assemble a complete edition with the four prepared classics.
8. Write versioned puzzle files, then update the edition manifest only after all referenced files exist and pass checks.

Prepare at least a week of dated fallback editions in advance. If a complete current-news edition is not ready by the cutoff, that date uses its prepared history, science or culture edition and is clearly labelled Evergreen. The classic games still publish normally.

Once the edition opens, retain its published puzzle identities. Handle a factual correction as an explicit revision with a visible note. Remove an invalid question from competitive comparison if necessary; preserve the player's completion. Freeze existing share links to their version and show a correction notice when applicable.

The publisher stores a private run report containing source failures, selected stories, validation failures, retries and model usage. Send an owner alert when publication fails or the reserve drops below 30 days. Regular operation is automated; the owner handles exceptions, source changes and additions to the checked content collection.

## Technical implementation

Use **React, TypeScript and Vite** for the interface and shared game engines. Produce a static web build with an installable PWA shell, a service worker and cached puzzle data. Vite supports this static deployment model. [Vite deployment documentation](https://vite.dev/guide/static-deploy.html).

| Layer | Implementation |
|---|---|
| Interface | React and TypeScript; shared game layout, keyboard, help, results and accessibility components |
| Game engines | Pure TypeScript modules for rules, valid moves, solution checks, scoring and state serialization |
| Hosting | Cloudflare Pages for the static web application |
| Published content | Cloudflare R2 object storage for versioned puzzle JSON, edition manifests and archive metadata |
| Scheduled publisher | Cloudflare Worker with Cron Triggers, bounded requests and model credentials stored as secrets |
| Content preparation | TypeScript batch scripts run through CI or the developer's content workflow to replenish classic puzzles and fallback editions |
| Local data | IndexedDB for puzzle progress, statistics, cached editions and favourites |
| Sharing | Permanent HTTPS links, Web Share where supported, clipboard fallbacks and client-generated images |
| Phone apps | Capacitor packages using the same interface and engines, with native sharing, storage integration and optional local reminders |

Capacitor provides a route from the web implementation to native iOS and Android containers. Package the game assets and starter content with the phone apps, then fetch subsequent editions through the same content service. [Capacitor documentation](https://capacitorjs.com/docs).

Use a common puzzle record with an ID, edition date, locale, game type, difficulty, content version, dictionary version where applicable, scoring version, payload and reveal. News records also reference their source facts. An edition manifest lists the exact puzzle versions for its date.

Persist progress under the complete puzzle identity. Save after every meaningful action. Add export/import so a player can move their history between the browser and the phone app without an account. Automatic cross-device sync is outside this local-data model.

After the first successful download, cache today's complete edition, recent history and several prepared classic sets. On a network failure, show cached content with its real date or a labelled evergreen edition. An initial web visit requires a connection; a downloaded app includes starter puzzles.

## Revenue and operation

All launch games, hints, sharing and the archive are free. Include a discreet Support Daypencil link on the home page footer, About page and result screens. Use a hosted contribution page on the web. Contributions unlock no game features.

Implement native contribution controls during phone packaging using the requirements applicable to each store and release market at that time. The donation screen should explain what support funds: hosting, content and continued upkeep.

Plan an initial software-service budget allowance of **$25 per month**, excluding developer time, source or puzzle licences, domain charges, payment fees and app-store costs. This is a planning allowance, not a verified total. Cloudflare Workers currently has a $5 paid-plan base, while storage and request charges depend on use; add a separate cap for model spending. [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [R2 pricing](https://developers.cloudflare.com/r2/pricing/).

Keep operating visibility focused on publishing health, content reserves, errors, bandwidth and costs. Player progress stays on the device. Provide a Report a Problem action that prepares a report with the puzzle ID and version for the player to send.

Maintain an operator checklist for dependency updates, source-access changes, domain renewal, content-bank replenishment and platform compatibility. The goal is reliable unattended daily publication with occasional maintenance.

## Build sequence

The sequence below delivers the full selected product. Durations are planning estimates for one experienced developer.

| Stage | Timing | Concrete deliverable |
|---|---|---|
| **1. Foundation and design** | Week 1 | Final game rules; design system; homepage and game layouts; source configuration; dictionary policy; puzzle schemas; repository and deployment setup |
| **2. Shared platform and first classics** | Weeks 2–3 | Navigation, keyboard, local persistence and result components; complete Daily Word and Sudoku engines and interfaces; dated puzzle routing |
| **3. Remaining classics and content reserve** | Weeks 4–6 | Letters and Mini Crossword; dictionary and clue-bank tools; classic puzzle generation and checking; initial 90-day reserve |
| **4. The news edition** | Weeks 7–8 | Correct, The Number, Where and Front Page; source adapters; structured-fact pipeline; publishing and evergreen fallback |
| **5. Sharing and daily use** | Week 9 | Permanent challenges, result cards, archive, favourites, PWA installation, offline cache, data export/import and web contributions |
| **6. Web release** | Weeks 10–12 | Mobile layout and accessibility fixes; content corrections flow; publication monitoring; production domain; public website and share-ready game pages |
| **7. Phone release** | Following 2–4 weeks | iOS and Android packages; native share integration; bundled starter content; optional local reminders; store assets and submission |

Budget **10–12 weeks for the complete web release and a further 2–4 weeks for phone packaging and submission**. These are working estimates; store review timing is external. Crossword content preparation and source integration are the largest schedule variables.

## Release requirements

Before public release, the implementation must meet these concrete checks:

- Every required game is playable from its dated link on supported phone and desktop browsers.
- Refreshing or closing the product preserves moves, guesses and notes.
- A challenge link received on a later date loads the original puzzle and scoring version.
- Repeated-letter feedback, Sudoku uniqueness, crossword crossings and Letters scoring pass engine checks.
- Each news answer is supported by its stored evidence; ambiguous alternatives are rejected and earlier rounds do not reveal later answers.
- A failed news run uses a complete, clearly labelled fallback while the classics remain available.
- A partial upload cannot become the current edition.
- Cached games remain playable when the connection drops.
- Keyboard access, colour-independent feedback, text scaling and reduced-motion behaviour work.
- The publisher's health report identifies failures and low reserves without exposing credentials.
- Donation access and a problem-reporting route are available.
- Production deployment supports rollback to the previous working application.

## Subsequent development

After the full release is operating, add **Archive** as a daily history bonus from the vetted collection and **Sort** as an occasional story-based extra when appropriate data exists. Additional small games should reuse the common layout, persistence, result and sharing systems.

A later social release can add live races or cooperative boards through a session service with temporary room codes. The initial permanent-link challenge system already lets people play the same puzzles online and compare results.

Keep the four classics and the short news edition as the stable core. Expand the collection deliberately while preserving immediate access, consistent rules, tasteful presentation and low routine upkeep.
