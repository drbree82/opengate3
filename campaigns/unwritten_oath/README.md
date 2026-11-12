# The Unwritten Oath

An original campaign and character pack for OpenGate. Install the whole `unwritten_oath` folder under `campaigns/`. Nothing in the main engine, shared rules data, Hollowmere, or Git history needs changing.

Start OpenGate and select **The Unwritten Oath**, then **The Witness** (or create a hero). Seris joins after her account in the opening hearing; Rowan joins after the stay is granted. Both are controllable party companions. Click a party member and choose to make them the leader. Oren supplies healing. Speak with Rowan and Seris at the sanctuary fire for their personal story; dismissed companions wait at sanctuary.

Quick launch from the project folder:

```sh
./run.sh --windowed -- --campaign=unwritten_oath --hero=witness
```

## What is playable

Seven locations, nine encounters, eight quests, a three-clue archive puzzle, three contact-charm conversations, four cloud approaches, restitution objectives, and two final relationship outcomes. The story runs from the first hearing to the annulment of both pacts and Rowan’s free decision about his future.

**Duration: approximately three hours is the design target, not a verified runtime.** A fast reader who bypasses fights may finish substantially sooner. The content needs a timed human playtest before being advertised as a three-hour adventure. Current tests establish that the story branches run, not how long or how challenging they feel.

Suggested first-play pacing budget: archive 20 minutes, market 20, ferry 30, Counting House 40, manor 30, tribunal and sanctuary scenes 40. These are allocation targets, not measurements. Optional dialogue, combat choices and side quests account for much of this budget; do not add artificial waits to meet it.

## The characters

**Seris** is a mortal woman descended from a succubus, lawful good in her convictions. An ancestor’s service pact was expanded into a claim over descendants. She has collected souls under coercion, knows the people she harmed, and wants to repair those wrongs. Her love for Rowan does not give her a right to his affection. Her past, threatened future, and responsibility for his captivity are the three strands of the story. She uses the existing rogue class and a clearly original campaign ancestry: +2 Dexterity, +2 Charisma, −2 Wisdom. Her base abilities cost 15 points. This is not the complete published tiefling racial package.

**Rowan** is an adult human warlock whose patron is Seris. He accepted power during a fire, but the archlord’s superior claim was concealed. He joins the expedition voluntarily under the stay. He remains a full player-controlled character: no patron domination, forced romance, or compulsory affection is implemented. His original campaign Pact Warlock class reuses the existing wizard chassis and spell progression with Charisma casting. It has ordinary daily slots and learned spells, not D&D pact slots or invocations. Existing spell entries are extended only within this campaign to recognise that class.

**Oren Vale** is a human cleric who insists rescue cannot create a new debt. **The Witness** is the player’s independent adventurer; the starter build is a human fighter. All four builds respect the existing 15-point budget.

The names, class adaptation and visual designs are provisional and easy to revise.

## Succubus Spittle

A permanent innate trait in Seris’s ancestry, activated at authored NPC dialogue choices through brief contact (the current scenes use a kiss). It resolves a visible **d20 + Seris’s Charisma modifier** check, DC 13, 14 or 15 depending on the NPC. This is an original Charisma-check implementation, not a published Pathfinder Will-save ability.

Success opens an information branch for that conversation. It does not make the target obedient, compel truth, grant romance, or produce admissible free testimony. Failure leaves documentary and ordinary persuasion routes available. One contact attempt per authored NPC scene prevents repeated-roll farming; the innate ability itself is never consumed. The sanctuary conversation acknowledges its moral consequences. It does not target Rowan or any other party character.

## Invisible Pheromone Cloud

At **Scout the guarded passage** points, Seris can attempt a visible Charisma check, DC 12–15. A failed attempt spends the daily use. A success temporarily suppresses hostility in the specifically listed living guard group. The guards remain on the map, block their occupied tiles, and award no defeat XP. Walk around them.

The duration is **ten exploration tile entries**, expiring on the tenth. Counters are saved; every traversable tile in those maps runs the duration script. Entering another map, resting, or beginning a fight ends the cloud. Long rest at the sanctuary fire renews the one daily use. There are no other authored rest points.

Only the guard groups listed in each approach are eligible. Human, dwarf and elf retainers are included; undead, animals, spiders, trolls and other unlisted creatures are excluded. The party is never a target. Its membership, control, approval and romantic choices do not change. This is guard distraction, not invisibility and not an effect placed on party members.

**Engine boundary:** these abilities operate at authored conversations and approaches. They are not universal free-target spell buttons. The existing engine cannot add arbitrary innate actions through campaign JSON alone. A universal version belongs in a separately authorised engine branch. After loading a save during a cloud, the first entered tile reapplies its saved guard state; the engine itself does not persist arbitrary entity hostility changes. No core engine workaround has been installed.

## Canon and original lore

Pathfinder 1e distinguishes demons from devils: a succubus is a demon. Being descended from one does not make a mortal incapable of goodness. The legacy reference explicitly allows good tieflings, including succubus descendants. See [Tieflings](https://legacy.aonprd.com/advancedRaceGuide/featuredRaces/tieflings.html) and [Demons](https://legacy.aonprd.com/bestiary/demon.html).

Infernal contracts have published precedents, but that does not make our particular contract terms canonical. See [Contract devils](https://legacy.aonprd.com/bestiary3/devil.html). This pack does not import their stat blocks or contract rules.

**Original campaign additions:** Seris, Rowan, all other named characters and locations, the unnamed archlord, the ancestral service bond, the forged hereditary rider, two linked soul claims, neutral archive jurisdiction, the stay of collection, both innate powers, the campaign ancestry and Pact Warlock class, and the final simultaneous annulment. Succubus ancestry and an infernal creditor are separate facts: her lineage does not determine which fiend claims her service.

No published setting characters, copied prose, additional rulebook statistics or third-party artwork are bundled. Existing core mechanics are reused through the project’s normal campaign overlay. Keep the repository’s licence notices with distribution.

## Route guide (spoilers)

1. Hear Seris’s explanation of why she cannot release Rowan; hear Rowan’s wishes. Read the ledger and preserve Mara’s testimony. Petition the registrar. Without the testimony, she explains what is missing and allows another petition.
2. Welcome Rowan as an equal party member. Take the archive exit to the market. Ask Tavin for the counterseal location. Charm, Diplomacy or the public receipt provides a route; failed charm does not lock the story.
3. At the ferry, hear Lysa’s memory of Mara. Optionally retrieve and return the bell. Cross to the Counting House.
4. Recover the counterseal, copy the names, and take Mara’s lantern after learning her identifying memory. Existing enemies can be fought or navigated around; the cloud affects the collectors, never the undead.
5. Use Camp to reach sanctuary. Release Mara without obligation. Speak to her separately and ask for voluntary testimony. Entrust the register to Oren. Return to the road.
6. At the manor, read all three inscriptions. Open the family seal with **Name, Will, Release** and preserve the original grant. A wrong answer causes no irreversible failure.
7. At court, reject soul substitutions and present the counterseal, original grant and free testimony. Fighting the mortal enforcers is optional and does not itself void the pact. Both claims are annulled together.
8. Return to sanctuary; choose **Speak with Rowan** at the fire. He may leave, or choose further rescue work without promising romance. Both are freedom endings.

## Validation

Run `campaigns/unwritten_oath/check.sh` from any directory. It runs the project’s unchanged checks and then this folder’s story tests. Tests cover both endings, failed charm recovery, cloud duration and daily reset, enemy/party separation, evidence gating, portraits, and save persistence. Full campaign smoke tests exercise every map, dialogue, trigger and fight; they use strengthened test heroes and are not a balance playtest.
