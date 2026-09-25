# SwiftDune vs the ScummVM Dune engine on the floppy release

SwiftDune can already draw the game but has almost none of the game logic. ScummVM has nearly the whole floppy game running from the executable's own data. The first step for SwiftDune is to keep the whole game state as one byte array: a copy of the executable's data segment (`vars`), as ScummVM does. The dialogue conditions, saves and every game rule then read and write the same bytes, and every later feature depends on it.

- **SwiftDune has:** HSQ decoding, sprites, `.SAL` rooms, the sky, the globe renderer, HERAD/OPL music, the whole intro and prologue, and the panel.
- **SwiftDune lacks:**
  - a reader for `DUNEPRG.EXE`;
  - room, character and location tables beyond hand-copied palace constants;
  - a dialogue engine: lines are hard-coded phrase numbers;
  - the flat map, travel, troops and saves;
  - real story progress: it uses invented milestones.
- **ScummVM still lacks:** smugglers' trade, Harkonnen raids, GO & SEARCH FOR EQUIPMENT, harvester breakdowns, the in-game night-attack picture, the floppy cockpit view, and the music choice per place.

Path shorthand used below:

- **SV** = `desert-frost-engine/third_party/scummvm/engines/dune/`
- **SW** = `SwiftDune/`

Three documents can be ported from directly, without reading any C++:

- `SV/FINDINGS.md`
- `desert-frost-engine/notes/research/gameplay-rules.md`
- `desert-frost-engine/notes/speedrun/battle-worm-spec.md`: a complete spec for troop marches, espionage, battles, worms and the final attack.

The Swift checkout already contains `reference/dune-rust`, whose map renderer is what `map.cpp` ports.

Confidence tags follow FINDINGS: **verified**, **reference** (from another reverse-engineering project and consistent with the data) and **guessed**. "(checked today)" means I confirmed it against the floppy files in `DuneFiles/` in this session. I did that by unpacking `DUNEPRG.EXE` with `Cryogenic-local/scripts/dune_unlzexe.py` and decoding HSQ files with `dune_dat.py`.

I checked every formula below with KaTeX (`throwOnError: true`): 28 expressions, no failures. I edited no project files. The only files I created were temporary ones in the scratchpad: the unpacked executable, a dump of the command strings, and a local KaTeX install.

Offsets written `ds:xx` are positions in the executable's data segment. Unless marked "floppy", they are the CD numbering that FINDINGS uses; §2.1 gives the conversion.

---

## 1. Feature matrix

Status: **done**, **partial**, **missing**. SV pointers are `file:line`; SW pointers are relative to SW.

| # | Feature | ScummVM | SwiftDune |
|---|---|---|---|
| 1 | HSQ files, sprites, RLE, scaling | done (`resource.cpp`, `sprite.cpp`) | done (`Engine/Resources/Resource.swift`, `Sprite.swift`) |
| 2 | Read `DUNEPRG.EXE`: LZEXE unpack, initial data segment | done: `world.cpp:106` `unpackLzexe`, `:177` `loadInitialData`, `:261` `findTables` | missing; only a hand-copied spice-density list (`Game/GameTypes.swift:217-248`) |
| 3 | Game state = the data segment (`vars`, 0x1500 bytes) | done (`dialogue.h:44-91`) | missing; separate Swift fields (`GameTypes.swift:257-541`) |
| 4 | Location table (70 records of 28 bytes) | done (`world.h:45-73`, `world.cpp:320-356`) | missing (density byte only) |
| 5 | Room tables and exits for every kind of place | done (`world.cpp:385-410`) | partial: palace exits hard-coded (`Game/Scenes/Game.swift:16-30`); what an exit means is wrong (§4.1) |
| 6 | Which sprite sheet each room uses (per-release slot table) | done (`world.cpp:423-438`) | partial: hard-coded per-room ranges (`Engine/Resources/Scenery.swift:124-153`); greenhouse wrong (§4.3) |
| 7 | Outdoor rooms: palace balcony and front, SIET0, VILG, FORT under the sky | done (`scene.cpp:497-635`) | partial: palace only (`Game/Scenes/Palace.swift:164-176`); wrong sky for room 1 |
| 8 | Character table; who stands on which marker | done (`world.cpp:450-540`, `scene.cpp:571-605`) | missing; hard-coded `[0: .leto]`, `[7: .jessica]` (`Game.swift:39`, `:55-58`) |
| 9 | Fremen in sietch room 2; FRM1-3 heads | done (`world.cpp:480-540`, `:780-826`) | missing; every sietch shows the intro's Harah and Stilgar (`Game.swift:196-226`, `Game/Scenes/Sietch.swift:55-65`) |
| 10 | Game clock and per-period events | done (`world.cpp:1010-1110`, `scene.cpp:2589-2600`) | partial: tick length right; start time, day formula, sun/moon and pausing wrong (`GameTypes.swift:342-372`) |
| 11 | Sky palette follows the clock | partial, mapping guessed (`scene.cpp:285-297`) | missing; always daytime in play (`Palace.swift:149-154`) |
| 12 | Panel: day number, sun/moon per period, companions, compass, greyed rows | done (`panel.cpp:160-229`) | partial (`Game/UI/UI.swift:93-229`) |
| 13 | Codes inside game text (nested lines, names, numbers, page breaks) | done (`text.cpp:84-164`) | missing; `Engine/Resources/Sentence.swift:45-69` returns raw bytes and strips `.` |
| 14 | CONDIT.HSQ condition evaluator | done (`dialogue.cpp:134-185`) | missing |
| 15 | DIALOGUE.HSQ engine: said flags, line actions | done (`dialogue.cpp:204-413`) | missing; hard-coded phrase numbers (`Game.swift:322-351`) |
| 16 | Talk verbs: TALK / COME WITH ME / STAY HERE / WORK FOR ME, companions | done (`scene.cpp:2202-2260`, `:2750-2800`) | partial: rows exist, no effects (`Game.swift:445-488`) |
| 17 | Talk screen: zoom on the speaker, portrait animation, speech balloon | done (`scene.cpp:2577-2748`) | partial (`Palace.swift:218-221`, `Game/UI/DialogueOverlay.swift:44-62`) |
| 18 | Story phases: dialogue events 11/12, phase triggers, phase callbacks | done (`scene.cpp:2405-2535`, `world.cpp:628-760`) | missing; invented milestones (`GameTypes.swift:391-409`) |
| 19 | Lines said on entering a room; place data for conditions | done (`story_scene.cpp:265-288`, `story.cpp:469-640`) | missing |
| 20 | Scripted " Continue..." scenes read from the EXE, final scene | done (`story_scene.cpp:74-232`) | missing in play (the intro has `Kiss.swift`) |
| 21 | Visions: queue, idle timers, VIS.HSQ dream, first vision in the desert | done (`story.cpp:367-440`, `story_scene.cpp:416-473`) | missing |
| 22 | COMM room: message list, new/seen, sender's line | done (`story.cpp:319-365`, `story_scene.cpp:236-243`) | fake: hard-coded screen (`DialogueOverlay.swift:65-120`, `Game.swift:543-559`) |
| 23 | Emperor's spice shipments | done (`story.cpp:74-317`) | partial: Duncan's offer list right; schedule, rating, reminders and ending missing (`GameTypes.swift:411-519`) |
| 24 | The book: topics, encyclopedia, journal | done; page layout is ScummVM's own (`book.cpp`) | partial: cover and one fixed phrase (`Game/Scenes/Book.swift:130-183`) |
| 25 | Flat map: MAP.HSQ + TABLAT, icons, scrolling, taps | done (`map.cpp:53-316`, `:439-494`) | missing |
| 26 | Globe with place icons | done (`scene.cpp:78-240`, `map.cpp:439-452`) | partial: globe drawn, no icons (`Engine/Resources/Globe.swift`, `Game/Scenes/Fresk.swift`) |
| 27 | Map menu, DUNE MAP popup, place popup | done (`scene.cpp:951-1000`) | missing |
| 28 | Travel: flight loop, periods, trail, spotting places, Harkonnen zone, arrival death | done (`scene.cpp:1302-1680`) | missing; `DesertWalk` is decoration (`Game/Scenes/DesertWalk.swift:118-130`) |
| 29 | Floppy flight view (dune pieces under the sky) | done, adapted from Swift's `Flight.swift` (`scene.cpp:1090-1152`) | done in the intro (`Game/Scenes/Flight.swift`), not used for travel |
| 30 | Ornithopters on the pad; take-off and landing (ORNYTK) | done (`scene.cpp:1174-1242`) | partial: intro only (`Game/Scenes/Ornithopter.swift`) |
| 31 | Open desert: WAIT, CALL A WORM, TAKE AN ORNITHOPTER | done (`scene.cpp:714-727`, `story_scene.cpp:386-412`) | missing |
| 32 | Troops: hiring, occupations, contact popup, MODIFY EQUIPMENT | done (`world.cpp:847-927`, `scene.cpp:1762-1986`, `story_scene.cpp:604-664`) | missing; placeholder enums (`GameTypes.swift:171-201`) |
| 33 | Spice mining, prospecting, stock, Harkonnen growth | done (`world.cpp:929-1110`) | missing |
| 34 | SEE RESULTS screen | done (`scene.cpp:1689-1760`) | wrong: template strings and a debug overlay (`Fresk.swift:163-212`) |
| 35 | Ecology: wind traps, bulbs, irrigation, vegetation, forts falling | done (`ecology.cpp`) | missing |
| 36 | Marches, espionage, battles, MASSIVE ATTACK, captain, worm riding, final attack | done (`troops.cpp`, `battle.cpp`, `scene.cpp:313-345`, `:731-737`) | missing |
| 37 | Harkonnen raids, smugglers' trade, harvester breakdowns, GO & SEARCH | missing | missing |
| 38 | Game menu on the globe: SAVE, LOAD, OPTIONS | done (`scene.cpp:1001-1046`, `:2076-2175`) | partial: only EXIT and quit confirm work (`Fresk.swift:241-291`) |
| 39 | Save/load in the DOS `DUNE21S<n>.SAV` format | done (`saves.cpp`) | missing |
| 40 | Mirror (palace room 9) | done (`scene.cpp:1244-1300`) | missing |
| 41 | Endings | done (`story_scene.cpp:477-520`) | missing |
| 42 | HERAD music on OPL | done, OPL2 (`music.cpp`) | done, OPL3 (`Engine/Audio/*`) |
| 43 | Which song plays where | placeholder: WORMINTR in the intro, then ARRAKIS (`dune.cpp:110,125`) | placeholder: ARRAKIS (`Game.swift:109-113`) |
| 44 | VOC sound effects | unused (`sound.cpp`) | partial (`Engine/Resources/Sound.swift`) |
| 45 | Floppy intro, credits, prologue | done (ported from swift-dune) | done (the original source) |

---

## 2. Data needed for each gap

### 2.1 The executable and the data segment (#2, #3, #4)

**LZEXE 0.91 unpacking** (verified; `world.cpp:106-175`):

1. The file starts with `MZ` and has `"LZ91"` at offset 28.
2. Header paragraphs are at offset 8 and CS at offset 22. `loader = (header paragraphs + CS) * 16`.
3. The packed data starts at `loader - packedParagraphs * 16`, where `packedParagraphs` is the word at `loader + 8`.
4. Read bits lowest-first from 16-bit little-endian words, loading a new word after the 16th bit.
5. Bit `1` means copy one literal byte.
6. Bits `00` then bits `a`, `b` mean a short match: length `2a + b + 2`, distance `byte - 256`.
7. Bits `01` mean a long match. Read `lo`, then `hi`:
   - distance = `((hi & 0xF8) << 5 | lo) - 8192`;
   - length = `(hi & 7) + 2`;
   - if that length is 2, read one more byte `n`: 0 ends the stream, 1 is a segment change (continue), anything else gives length `n + 1`.

**Where the data segment is** (checked today):

- The unpacked image is 74,245 bytes, has no MZ header and starts with code.
- The data segment is at image offset **0xECF0 (60656)**.
- Find it by the 12-byte signature `00 00 02 00 0A 20 80 01 20 00 00 0A`, then copy 0x1500 bytes into `vars`.

**Converting CD offsets to floppy offsets** (verified; `world.h:224-229`). FINDINGS and the disassembly notes number everything as on the CD. The floppy data segment is 2 bytes shorter in one range and 13 bytes longer after it:

| CD offset | Floppy offset |
|---|---|
| below 0x1158 | the same |
| 0x1158 to 0x11BF | CD offset - 2 |
| 0x11C0 and above | CD offset + 13 |

Floppy positions of the main tables (checked today):

| Table | Floppy offset |
|---|---|
| Palace room table | 0x1232 |
| Room pointer table (0x34 words, indexed by place type) | 0x13D1 |
| Name table | 0x11F8 |
| Part of the segment kept in saves | 4718 bytes (0x126E) |

**Initial values** (checked today):

- Time (ds:2) = **2**.
- ds:4 to ds:0B = `0a 20 80 01 20 00 00 0a`: the throne room.
- Charisma, story phase, rallied-troop count: 0.
- ds:C7 = 0; ds:FC = 1.
- Contact range (floppy 0x1174) = 1.
- Companion slots ds:1152/1153 = 0xFF (empty).

**Named variables** (CD offsets; verified or reference; `world.h:246-265`):

| Offset | Meaning |
|---|---|
| 0x00 | random word |
| 0x02 | time |
| 0x04 | room |
| 0x05 | place type |
| 0x07 | location + 1 |
| 0x08 | current scene (0xFF = open desert) |
| 0x0A | Paul's event bits: 0 vision, 1 drank the Water of Life, 3 heard of it, 4 met Stilgar, 5 met Kynes, 6 rode a worm |
| 0x0B | current room |
| 0x0E | persons met |
| 0x10 | persons travelling with Paul |
| 0x12 | persons in the room |
| 0x14 | person being talked to |
| 0x23 | pending room action |
| 0x27 | known sietches |
| 0x28 | rallied troops |
| 0x29 | charisma (capped at 200) |
| 0x2A | story phase |
| 0x9F | bargaining choice |
| 0xA0 | spice stock, a word, in 10 kg units |
| 0xB4 | Duncan's four offers (words) |
| 0xBC | the Emperor's demand |
| 0xBE | how well the last shipment met the demand |
| 0xBF | shipment flags |
| 0xC0 | amount agreed with Duncan |
| 0xC2 | final-attack stage |
| 0xC3 | number of demands so far |
| 0xC8 / 0xC9 | message count / unread count |
| 0xCF | days to the next shipment |
| 0xEA | vision type |
| 0x1152 / 0x1153 | companion slots |
| 0x1176 | contact range |
| 0x1179 | ten message words |
| 0x1190 | vision queue: a count byte, then 10 pairs of (id word, place word) |

**Location record**: 28 bytes at `0x100 + 28*i`, 70 records, ended by `FF FF`. Verified (`world.cpp:320-345`).

| Byte(s) | Field |
|---|---|
| 0 | first-name id; the name is COMMAND `first - 1` |
| 1 | last-name id; the name is COMMAND `11 + last` |
| 2-3 | longitude, u16 |
| 4-5 | latitude, i16 |
| 6-7 | cell offset in MAP.HSQ (set at new game) |
| 8 | type: below 0x20 a sietch (its value picks the room table), 0x20 Atreides palace, 0x21-0x27 village, 0x28-0x2F fortress, 0x30 Harkonnen palace |
| 9 | first troop at the place |
| 10 | status: 0x80 hidden, 0x40 prospected, 0x20 wind trap, 0x10 visited, 0x08 held by the Atreides, 0x04 saboteurs, 0x02 battle, 0x01 vegetation |
| 11 | phase from which it can be found (0xFF never); reused later as a radius or a day |
| 12-15 | vegetation disc: centre longitude (word), latitude, progress |
| 16 / 17 / 18 / 19 | spice field / spice amount / density / mining remainder |
| 20-26 | equipment counts: harvesters, ornithopters, krys knives, laser guns, weirding modules, atomics, bulbs |
| 27 | water, or the wind-trap assembly progress |

Specific places (checked today):

- Location 0 is the Atreides palace; location 1 the Harkonnen palace.
- Location **12** is Carthag-Tuek (sietch type 0, troop 1).
- Location **11** is Carthag-Timin (troop 3, the prospectors).
- Location 2 is an Arrakeen fortress.

**Character record**: 16 bytes at `0xFD8 + 16*i`. Verified.

- Bytes 0-3: room, place type, 0x80, location + 1 (0xFF means away).
- Byte 14: the character's index.
- Byte 15: flags.
- A character is in the current room when bytes 0-3 equal ds:4 to ds:7 (`world.cpp:465-477`).
- Anyone travelling with Paul (bit `i` of ds:10) stands wherever Paul is.

Initial floppy records (checked today):

| Character | Room | Place type | Location |
|---|---|---|---|
| Leto | 10 | 0x20 | 0 |
| Jessica | 4 | 0x20 | 0 |
| Thufir | 8 | 0x20 | away |
| Duncan | 4 | 0x20 | away |
| Gurney | 2 | 0 | 12 |
| Stilgar | 2 | 4 | 45 |
| Kynes | 2 | 0x10 | 62 |
| Chani | 3 | 5 | 26 |
| Harah | 3 | 7 | 16 |

**Troop record**: 27 bytes at `0x8AA + 27*(id-1)`, 68 troops. Troops 1-26 are the sietch Fremen (not hired); 27-67 are Harkonnen garrisons. Full table in battle-worm-spec §0.1.

| Byte | Field |
|---|---|
| 1 | next troop at the same place |
| 3 | occupation: low 4 bits the job; 0x10 stopped, 0x20 captured, 0x40 moving, 0x80 not hired |
| 4 | data-segment offset of its location record |
| 6 / 8 | longitude / latitude |
| 0x0A | time the job started |
| 0x0C / 0x0E | job counters |
| 0x10 | bit field; 0x80 = Harkonnen troop |
| 0x12 | speech bits; low 4 bits = region |
| 0x14 | day rallied |
| 0x15 | motivation |
| 0x16 / 0x17 / 0x18 | spice, army, ecology skill (cap 0x5F) |
| 0x19 | equipment: 0x80 harvester, 0x40 ornithopter, 0x20 krys, 0x10 laser, 0x08 weirding, 0x04 atomics, 0x02 bulbs |
| 0x1A | men / 10 |

**New-game pass** (verified against the original floppy's new-game save; `world.cpp:1164-1222`):

1. Build a histogram of MAP2.HSQ's 50,681 bytes, each count starting at 7.
2. For each place:
   - Use `row = |latitude|`. TABLAT.BIN has 8 bytes per row. Read two **big-endian** words: `rowOffset` at `8*row` and a half-length at `8*row + 2`. `cells` = 2 × half-length.
   - The cell under the longitude, rounded: $c = \lfloor \mathrm{lng}\cdot \mathrm{cells} / 2^{16} \rfloor + (\lfloor \mathrm{lng}\cdot\mathrm{cells}/2^{15}\rfloor \mathbin{\&} 1)$.
   - `offset = 0x62FC + rowOffset + c`, or `- rowOffset` for a negative latitude.
   - Store the snapped longitude $\lfloor c\cdot 2^{16}/\mathrm{cells}\rfloor$ at byte 2 and `offset` at byte 6.
   - Byte 16 = `MAP2[offset]`; byte 17 = `histogram[MAP2[offset]] >> 4`.
3. For each troop at a place:
   - Set byte 4 to the place pointer and bytes 6/8 to the place's longitude and latitude.
   - Set byte 18 to `(old & 0x70) | region`, where region = `firstName & 15`.
   - Flip bit 7 once for each of region > 3, region > 5 and region > 9.
4. The live map is MAP.HSQ with bit 6 set on every place's cell.

### 2.2 Rooms, exits, doors, sheets (#5 to #9)

**Room table.** `word(pointerTable + 2 * placeType)` points to 5-byte records: `code, up, right, down, left`.

- A table ends at the next higher pointer, or at a code of 0xFF.
- The palace table is capped at 12 rooms.
- Sietch types 0x11-0x1F reuse the tables of 0x01-0x0F.

**Room code** `code`: the `.SAL` room is `(code - 1) & 15` and the sheet slot is `(code - 1) >> 4`. The floppy slot list (verified):

| Slot | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Sheet | POR | PROUGE | COMM | EQUI | BALCON | CORR | SIET0 | SIET1 | VILG | FORT | BUNK | FINAL | SERRE | BOTA | PALPLAN | SUN |

The `.SAL` file by place type: below 0x20 `SIET.SAL`, 0x20 `PALACE.SAL`, 0x21-0x27 `VILG.SAL`, otherwise `HARK.SAL`.

**Floppy palace table** (checked today):

| Room | Code | Sheet / SAL room | Up | Right | Down | Left | Notes |
|---|---|---|---|---|---|---|---|
| 1 | 76 | BALCON / 11 | 2 | 0 | 253 | 0 | palace front, outdoors |
| 2 | 58 | EQUI / 9 | 7 | 0 | 1 | 0x8C | phase 4 lowers the code to 57 (EQUI / 8): the stillsuits are stored |
| 3 | 207 | SERRE / 14 | 0 | 0 | 0 | 11 | greenhouse |
| 4 | 2 | POR / 1 | 10 | 0 | 7 | 0 | |
| 5 | 75 | BALCON / 10 | 0 | 0 | 0 | 10 | balcony, outdoors |
| 6 | 21 | PROUGE / 4 | 11 | 0 | 0 | 0 | |
| 7 | 93 | CORR / 12 | 4 | 0x8B | 2 | 0x88 | |
| 8 | 38 | COMM / 5 | 0 | 0x87 | 12 | 0 | COMM room |
| 9 | 3 | POR / 2 | 0 | 0 | 10 | 0 | mirror room |
| 10 | 1 | POR / 0 | 9 | 5 | 4 | 0 | throne room, where the game starts |
| 11 | 4 | POR / 3 | 0 | 0x83 | 6 | 7 | |
| 12 | 94 | CORR / 13 | 8 | 2 | 0 | 0 | |

**What an exit value means** (verified; `scene.cpp:759-775`, `:900-912`):

| Exit value | Meaning |
|---|---|
| 0 | no exit |
| 1-127 | a room of this place |
| bit 7 set, value below 252 | **a locked door** to room `value & 0x7F`: no arrow, cannot be used |
| 252-254 | leave the place: open the flat map to choose a destination |
| 255 | the village's "up" exit; meaning unknown |

**Doors opened by the story.** A phase callback clears bit 7 of the exit byte at `palace table + 5*(room - 1) + 1 + direction`, with direction 0 up, 1 right, 2 down, 3 left. I derived these from the CD offsets in `world.cpp:628-760`:

| Phase | Door opened |
|---|---|
| 0x08 | room 2 left, to room 12 |
| 0x0C | room 7 left and room 8 right: the COMM room |
| 0x1C | room 7 right, to room 11 |
| 0x54 | room 11 right, to room 3 (the greenhouse) |

**Floppy sietch tables** (checked today). Room 1 is always code 97 (SIET0 / 0, outdoors) with exits (2 or 3, 254, 253, 252). The other rooms, as SIET1 room numbers:

| Type | Room 2 | Room 3 | Room 4 | Room 5 |
|---|---|---|---|---|
| 0 to 4 | SIET1/1 to SIET1/5 (type + 1) | - | - | - |
| 5 | SIET1/6 | SIET1/1 | - | - |
| 6 | SIET1/7 | SIET1/10 | - | - |
| 7 | SIET1/9 | SIET1/1 | - | - |
| 8 | SIET1/8 | SIET1/10 | SIET1/12 | - |
| 9 | SIET1/11 | SIET1/10 | SIET1/12 | - |
| 0xA | SIET1/3 | SIET1/10 | SIET1/12 | - |
| 0xB | SIET1/4 | SIET1/1 | SIET1/12 | - |
| 0xC | SIET1/5 | SIET1/2 | SIET1/12 | - |
| 0xD | SIET1/6 | SIET1/1 | SIET1/12 | - |
| 0xE | SIET1/7 | SIET1/10 | SIET1/12 | - |
| 0xF | SIET1/9 | SIET1/1 | SIET1/12 | - |
| 0x10 | SIET1/11 | SIET1/10 | SIET1/12 | BOTA/13 |

Read the exits from the table rather than copying them.

Other place types (checked today):

- **Village:** one room, code 129 (VILG / 0), exits (255, 254, 253, 252).
- **Fortress:** 145 FORT / 0 with exits (2, 254, 253, 252); 167 BUNK / 6 with exits (0, 3, 1, 0); 166 BUNK / 5 with exits (0, 0, 0, 2).
- **Harkonnen palace:** room 1 is code 149 (FORT / 4); room 2 is code 168 (BUNK / 7), the Baron's hall where the game ends. (guessed) The bytes after room 2 are not room data, so stop at 2 rooms.

**Drawing outdoor rooms** (verified or measured; `scene.cpp:523-603`):

1. A room is outdoors if it is palace SAL room 10 or 11, or uses slot 6, 8 or 9 elsewhere (SIET0, VILG, FORT).
2. Sky:
   - Palace SAL room 11 (room 1, the front) uses the **large** sky: tiles 4-7, 30 rows each, 200 px wide.
   - Every other outdoor room uses the **narrow** sky: tiles 0-3, 20 rows each, 320 px wide.
3. Outside the palace, also fill (0,78)-(320,152) with colour 190.
4. For the palace's outdoor rooms, draw BALCON frame 2 at (0,0) first.
5. Palette order: first the panel colours (PERS.HSQ gives 1-15 and 224-239), then the room sheet (which also sets 240-255), then force colour 0 to black.
6. The outdoor sheets have no palette of their own and use the sky's colours 128-222.

**Who stands on which marker** (verified for Leto; `scene.cpp:571-605`):

1. List the people in ascending character order. That is the characters present, plus:
   - the Fremen of a sietch (§2.10);
   - the smuggler (13) in every room of a type-0x21 village;
   - the Harkonnen captain (12) in fortress room 3 when a defeated Harkonnen troop is there.
2. `markers` is the room's marker count, the first byte of the room in the `.SAL` file.
3. Each person takes slot `(character number + ds:C7) mod markers`, or the first free slot if that one is taken.
4. **Marker `j` shows the person in `slots[markers - 1 - j]`.** Character 0 (Leto) therefore stands on the throne room's **last** marker, at (186,53).
5. The figure is PERS frame `2 * min(character, 15)`, or `2 * (14 + troopId % 3)` for a Fremen.
6. A scripted scene's opcode 00 writes its cast straight into the slots.

**Parked ornithopters** (`scene.cpp:1174-1242`):

- Shown in room 1 only: `min(3, the place's ornithopter count)`, and the palace always shows at least one.
- The pad is at (149,57) in a sietch and (202,73) elsewhere. Each further ornithopter is 70 px right and 10 px lower.
- ORNYTK.HSQ frames: body 0; hub 1 at +(6,30); legs `2 + clamp(frame - 15, 0, 5)` at +(4,50); wings `8 + min(frame, 14)` at +(-81,-3).
- Take-off plays frames 1 to 33 at 100 ms each. From frame 15 on, the craft moves left by `5 * (frame - 14)` and up by `(frame - 14)^2 / 2`. Landing plays the frames in reverse.

### 2.3 Clock, day and sky (#10, #11, #12)

Verified; `gameplay-rules.md` "Clock", `world.cpp:1010-1126`.

- **Period length.** The timer runs at $1193182/5957 \approx 200.3$ Hz. One period is 12,000 ticks, about 59.9 s (ScummVM uses 59,906 ms). The Swift doc argues for 12,001 ticks (59.915 s); that is plausible.
- **Day and period.** There are 16 periods a day, `period = time & 15`. The day shown is $\left(\lfloor (t+3)/16 \rfloor \bmod 365\right) + 1$ (`scene.cpp:279-283`). A new game starts at time **2**.
- **Pausing.** The clock runs only in room and map views. It stops in dialogues, the book and menus (`scene.cpp:2594-2597`).
- **New finding** (checked today; neither engine uses it): floppy COMMAND **266** holds sixteen 10-character time labels, one per period. Period 0 is "4.30 a.m." and period 13 is "12.00 a.m.". Midnight is exactly where `(t+3) >> 4` changes, which confirms the day formula. (guessed) The save rows "Log 1: DAY 0 / 12.00 a.m." are probably built from `t >> 4` plus `substring(266, 10 * (t & 15), 10)`. ScummVM's "24 units a day" is a stated placeholder.
- **Sun and moon on the panel** (verified; table at ds:1E7E; `panel.cpp:184-193`). ICONES 0x4A is the sun and 0x4B the moon; "-" means not drawn.

  | Period | Sun | Moon |
  |---|---|---|
  | 0 | (6,187) | (25,186) |
  | 1 | (6,186) | (26,188) |
  | 2 | (6,185) | - |
  | 3 | (7,183) | - |
  | 4 | (9,182) | - |
  | 5 | (10,181) | - |
  | 6 | (13,181) | - |
  | 7 | (16,181) | - |
  | 8 | (18,182) | - |
  | 9 | (20,183) | - |
  | 10 | (20,185) | - |
  | 11 | (20,186) | (8,188) |
  | 12 | (20,187) | (9,186) |
  | 13 | - | (12,183) |
  | 14 | - | (17,182) |
  | 15 | - | (23,183) |

  The day number is centred between x = 7 and x = 29 at y = 189, in colour 250.
- **Sky palette** (guessed in ScummVM). SKY.HSQ palette record = entry `8 + n` of its offset table.

  | Periods | Sky | Record `n` |
  |---|---|---|
  | 0 | sunrise | 16 |
  | 1-10 | day | 1 |
  | 11-12 | sunset | 6 |
  | 13-15 | night | 3 |

  The real mapping (`sub_138B4`) is not decoded.
- **What each period runs**, in order:
  1. Troop jobs, unless the final-attack stage ds:C2 is 7 or more.
  2. Period 3: the shipment rules.
  3. Period 8: the shipment reminder vision (0x30B).
  4. Period 15, if a random bit is set: every Harkonnen troop with 1-199 in byte 26 gains 1.
  5. Period 0: the ecology new-day walk.
  6. Re-stage the current place for the conditions.
  7. Period 0: Harkonnen production and today's spice.
     - `ds:A8 = S + rand(S/16 + 1)`, where S is the sum of `density / 8` over fortresses, the Harkonnen palace and hidden places.
     - `ds:A6 = stock - ds:1170`, then `ds:1170 = stock`.

### 2.4 Game text (#13)

Verified; `text.h:37-62`, `text.cpp:84-164`.

**Files.** Each text file is a table of 16-bit offsets (count = first word / 2), then strings ending in 0xFF.

**Text ids.** Ids are 1-based. Take `id - 1`: if bit 11 is set, read the phrase file at index `(id - 1) & 0x7FF`; otherwise read COMMAND.

**Codes inside a string:**

| Byte(s) | Meaning |
|---|---|
| 0x0D | line break |
| 0xFE | page break: the player taps for the rest |
| 0x80, hi, lo | another string, by id (big-endian) |
| 0x81-0x8F | another string whose id is the word at `nameTable + 2 * (code & 15)` (floppy name table 0x11F8) |
| 0x91 v | the byte `vars[v]` as a decimal number |
| 0x92 v | the word at `vars[v]` as a decimal number |
| 0xA0-0xCF | literal; the font draws the low 7 bits |
| 0xD0 | skip the next 2 bytes |
| 0xD1 | skip the next 4 bytes |
| 0xD2-0xEF | skip the next byte |
| 0xF0-0xFD, 0xFF | end of the string |
| other bytes below 0x20 | layout hints; drop them |

**The name table.** Words 1 and 2 (codes 0x81 and 0x82) are the current place's first and last name. Set them to the ids `firstName` and `12 + lastName` whenever Paul moves (`world.cpp:370-382`).

**Useful floppy COMMAND1 numbers** (checked today; ScummVM looks rows up by their text because CD numbering differs):

| Index | Text |
|---|---|
| 66-72 | troop contact verbs |
| 106-108 | SPECIALIZE IN SPICE / ARMY / ECOLOGY |
| 109-132 | names of persons (123 "Fremen", 124 "Fremen Chief") |
| 133-137, 139 | talk verbs (139 = WORK FOR ME) |
| 141 | SEE DUNE MAP |
| 142 | LOOK AT MIRROR |
| 143-144 | the two battle verbs |
| 149 | " Continue..." |
| 150 | "  Cancel" |
| 152-161 | desert and flight verbs |
| 164-174 | globe and options menus |
| 175-180 | endings |
| 178 | Harkonnen-zone warning |
| 181-191 | layout templates for the results screen |
| 202-204 | COMM room rows |
| 213 | DUNE MAP popup |
| 214-218 | book topics |
| 226-228 | ACCEPT / REFUSE / ARGUE |
| 230-245 | book speaker headers |
| 253-263 | music, save-slot and save-status rows |
| 266 | time labels |
| 277-289 | cast list |

### 2.5 CONDIT and DIALOGUE (#14 to #16, #19)

**CONDIT.HSQ** (verified; floppy file 10,764 bytes, 707 conditions; `dialogue.cpp:88-185`). A condition is an operand, then pairs of (operator, operand), ended by 0xFF.

- Condition `k` counts from 1 and starts at the word at `(k - 1) * 2`. Condition 0 is always true.
- **Operands.** Read a kind byte `K`:
  - below 0x80: read a byte `n`. The value is `vars[n]` if `K` is 1, otherwise the word at `n`.
  - 0x80: a one-byte constant follows.
  - above 0x80: a little-endian word constant follows.
- **Operators** (`op & 0x1F`). Comparisons give 0xFFFF or 0.

  | Code | Operation |
  |---|---|
  | 0 | equal |
  | 2 | less than (unsigned) |
  | 4 | greater than (unsigned) |
  | 6 | not equal |
  | 8 | less or equal (signed) |
  | 0x0A | greater or equal (signed) |
  | 0x0C | add |
  | 0x0E | subtract |
  | 0x10 | AND |
  | 0x12 | OR |

- **Precedence.**
  - An operator with bit 7 set is deferred: push (current value, operator) and start again from the next operand.
  - An operator without bit 7 is applied at once.
  - At the end, fold the pushed entries starting from the oldest.
- The condition is true when the result is not zero.

**DIALOGUE.HSQ** (verified; the floppy file is **4,464 bytes**, and its split word at 0x60 is **0x920**).

- It holds 17 characters × 8 lists.
- The list for character `c`, list `l` starts at `word(2 * (8c + l))`.
- Each list is 4-byte entries ending in `FF FF`.

**One entry** (`b0` to `b3`):

- `b0`: bit 7 said, bit 6 repeatable, bits 4-5 mask group, bits 0-3 action.
- Condition = `(b2 >> 6) << 8 | b1`.
- Book topic = `(b2 >> 2) & 15`: 1 politics, 2 Paul on Dune, 3 spice, 4 the Fremen.
- Sentence `s = (b2 & 3) << 8 | b3`, counting from 1. The text is phrase `s - 1` of **PHRASE12** if the entry's offset is at least the split, otherwise of PHRASE11.

**Character order:** 0 Leto, 1 Jessica, 2 Thufir, 3 Duncan, 4 Gurney, 5 Stilgar, 6 Kynes, 7 Chani, 8 Harah, 9 the Baron, 10 Feyd, 11 the Emperor, 12 the Harkonnen captain, 13 the smuggler, 14 Fremen, 15 Fremen chief, 16 messages / book / phase triggers.

**Portrait sheets** in the same order: LETO, JESS, HAWA, IDAH, GURN, STIL, KYNE, CHAN, HARA, BARO, FEYD, EMPR, HARK, SMUG. Fremen use FRM1-3, chosen by `troopId % 3`.

The "said" flags are written into this table at run time, and saves store the whole 4,464-byte table.

**How a conversation runs** (verified; `dialogue.cpp:258-413`, `scene.cpp:2260-2560`):

1. Starting a talk with character `c` sets bit `c` in "persons met" (ds:0E) and sets "talking to" (ds:14) to `1 << c`.
2. Walk the current list and pick the first entry whose condition holds, skipping entries that are said, not repeatable and share a bit with the mask. The mask is 0x80 for normal talk.
3. Show that entry's text, split into pages at 0xFE.
4. After its last page:
   - run its action;
   - set its said bit;
   - if it has a topic and was not said before, record `c << 11 | offset/4` for the book.
5. Continue searching after that entry. At the end of a list, go to the next list while the list number is not a multiple of 4. So TALK TO ME walks lists 0-3.

**Which list each situation reads:**

| Situation | Character | List | Mask | Notes |
|---|---|---|---|---|
| COME WITH ME / WORK FOR ME | the speaker | 5 | 0x20 | one line only; its action runs before the result is checked |
| STAY HERE | the speaker | 6 | 0x20 | one line only |
| Troop chief's contact lines | 15 | 2 | | |
| Line on entering a room; COMM sender | the speaker | 4 | | |
| Scripted scene lines | the speaker | 7 | | |
| Phase triggers | 16 | 7 | 0x80 | text not shown, only the action fires; run twice at new game |
| Visions | 16 | 4 | | ds:EA = the vision type |

**Actions:**

| Action | Effect |
|---|---|
| 1 | keeps the verb's gate (the verb succeeds) |
| 2 | drops the gate (a refusal) |
| 3 | scripted scene chosen by phase (below 0x14: 0x12F8; below 0x18: 0x134F; below 0x30: 0x1370; else 0x12DB); the talk ends |
| 4 / 5 | bargaining menu ARGUE / ACCEPT / REFUSE / WHAT?; the choice sets ds:9F (1 accept, 2 refuse, 3 argue) and adds 1 to ds:1A |
| 6 | end the talk after this line |
| 7 | gate = 0x80 |
| 8 / 9 / 15 | the speaker's special effects, below |
| 10 | lip sync on the CD; ignore |
| 11 | phase + 1, ds:FF = 0; at phase 1 set byte 3 of Duncan's record to 1; then run the phase triggers |
| 12 | set the phase to `(phase & 0xFC) + 4` |
| 14 | ds:C2 + 1 |

Actions 3, 8, 9 and 15 run every time their line is spoken. Actions 11, 12 and 14 run only the first time.

**Action 8, by speaker:**

- **Jessica** raises the contact range:
  - the first time from 1 to 30, with charisma + 10;
  - each later time + 20;
  - if ds:0A bit 1 is set, charisma + 40 and the range becomes unlimited (0xFFE2);
  - then ds:D5 = 0 if the range is at least 100, else `0x80 - range/6`.
- **Duncan** makes his shipment offers (§2.7).
- **Stilgar** handles the Water of Life:
  - ds:0A |= 8;
  - if ds:9F is 1 (accepted) and charisma is below 100, Paul dies (ending COMMAND 176);
  - if ds:9F is 1 otherwise, ds:0A |= 2, ds:D5 = 0xFF, and 3 periods pass.
- **Character 12** reveals the place whose pointer is at ds:11CE (floppy 0x11DB).
- **The smugglers** set phase 0x3C, ds:9E = rand & 3, byte 3 of their record = today, and ds:1A = 0.

**Actions 9 and 15:**

- Action 9: Duncan confirms the agreed amount (§2.7); Stilgar launches the final attack (spec §6.3).
- Action 15: Jessica adds 1 to ds:F5; Duncan closes the bargaining (§2.7).

**Verbs** (`scene.cpp:2202-2258`):

- **COME WITH ME / STAY HERE** toggles bit `c` of ds:10 when the gate holds.
  - Companions go into slots ds:1152/1153 (the record's byte 14).
  - A third companion sends the first one home: that record gets Paul's position.
  - STAY HERE writes Paul's position into the record.
  - Show companions on the panel as ICONES `0x41 + id`.
- **WORK FOR ME** is offered only for person 14.
  1. Run the charisma check (§2.10).
  2. Set ds:23 = 0 if it passed, 2 if not, before the line.
  3. If the gate still holds afterwards, rally the troop and continue the talk as its chief with GIVE ORDERS TO TROOP.
- **Talk rows:** TALK TO ME; then WORK FOR ME, GIVE ORDERS, or COME WITH ME / STAY HERE; then STOP TALKING.

**Entering a room** (`story_scene.cpp:265-288`). On every room move and every arrival:

1. Set ds:23 = 5.
2. Mark the place visited:
   - status |= 0x10;
   - ds:25 + 1 if it is a sietch;
   - ds:26 = 0xFF on the first visit.
3. The first person present who has a list-4 line whose condition holds says it.
4. Set ds:23 = 0.

**Place data for conditions** (verified; `story.cpp:469-640`). Recompute on room entry, every period, and for troop talks.

- ds:11CE is the place pointer.
- ds:4E = `first << 8 | last`; ds:4D the type; ds:50 the region; ds:51 the status; ds:52 the density; ds:54 the water; ds:55-5B the equipment; ds:53 a mask of free equipment.
- ds:94 / ds:96 are the Harkonnen / Fremen strength and ds:9C the balance (spec §3.3).
- ds:60-92 are troop counts.
- ds:F7 records whether Gurney, Stilgar or Chani are there.
- Nearest places use $d=\max(\lvert\Delta \mathrm{lng}\rvert \gg 8, \lvert\Delta \mathrm{lat}\rvert)$. Five slots, each with its compass direction (octant):

  | Slot | Nearest |
  |---|---|
  | ds:CA | any place |
  | ds:D0 | known sietch |
  | ds:D6 | hidden sietch that can be found now |
  | ds:DC | known fortress |
  | ds:E2 | hidden fortress |

- ds:11FD = `0xDA + octant` of the findable sietch. This feeds lines like "there is a sietch very near, northwards".

### 2.6 Story phases, scenes, visions, COMM (#18, #20 to #22)

**Setting a phase** (`scene.cpp:2503-2519`). The phase only ever goes up. Then set ds:FF = 0 and run the phase triggers. If the new phase is at most 0x6C and a multiple of 4, run its callback from the table below.

**Phase callbacks** (`world.cpp:628-760`). Offsets are CD numbering, so convert them. "Reveal" means discover the place: clear bit 0x80, set byte 11 to 0, and add 1 to ds:27 for a sietch.

| Phase | Effect |
|---|---|
| 0x04 | lower palace room 2's code by 1 (stillsuits stored); reveal places 10 and 17 |
| 0x08 | open room 2's left door |
| 0x0C | open the COMM-room doors; word 0x121D = 0xFFFF; play scene 0x1321 |
| 0x10 | Leto to room 5, Jessica to room 9; message 0x10B |
| 0x14 | Leto to room 10; reveal 21, 22, 23 |
| 0x1C | open room 7's right door; word 0x1217 = 0xFFFF |
| 0x20 | Thufir comes to the palace; reveal 64 |
| 0x28 | reveal 64 |
| 0x2C | word 0x1154 = time; move Gurney, Thufir and Jessica; word 0x1201 = 0x0109; charisma + 20; ds:0A \|= 0x10; reveal 45, 44, 46, 48, 49 |
| 0x30 | vision 4; message 0x1409 |
| 0x34 | Jessica to room 10, unless she is in room 8 |
| 0x38 | Leto leaves (location 0xFF) |
| 0x40 | Harah flags \|= 2 |
| 0x44 | reveal 26 |
| 0x48 | charisma + 10; scene 0x1313; Chani flags = (flags \| 0x10) & ~2; var 0x1178 = ds:28 + 2; reveal 27, 28, 25, 69 |
| 0x4C | var 0x1141 + 1; Jessica to palace room 2; vision 0x105 |
| 0x50 | ds:0A \|= 0x40; charisma + 40; Jessica to room 9 |
| 0x54 | open room 11's right door; word 0x1211 = 0xFFFF |
| 0x58 | ds:0A \|= 0x20; scene 0x12FB; reveal 63, 60, 61, 67, 65 |
| 0x5C | Kynes to room 5; var 0x11D0 + 12; word 0x1156 = day + 3; var 0x1141 + 1 |
| 0x60 | ds:FF = 0; Chani goes to room 2 of the Harkonnen palace |

Other phase changes:

- Discovering Tuono-Harg (names 3 and 6) sets phase 0x10.
- Rallying the `var(0x1178)`-th troop sets phase 0x4C.
- The first worm ride sets phase 0x50.
- Entering room 2 of the Harkonnen palace sets phase 0xC8 and plays scene 0x128F.

**Scripted scenes** (verified). They are read from the executable, not copied into code. On the floppy, the unpacked-image offset is the **CD offset + 0x3CA** (checked today: 0x16C2 holds `0E 10 FF`).

Each opcode byte is twice the action number:

| Bytes | Meaning |
|---|---|
| `00 room n cast…` | switch to that room; the `n` cast bytes fill the marker slots |
| `12 …` | the same, with a transition |
| `02 who` | that character's next list-7 line |
| `04` | redraw |
| `06 who` | show the head without speaking |
| `08` | wait for " Continue..." |
| `0A` | advance to period 13, then CHANKISS sprite 0 at (78,33) |
| `0C` | CHANKISS sprite 1 at (26,4) |
| `0E` / `10` | the prospector's lesson: chief 15's list-7 lines |
| `14` | FINAL.HSQ sprites 0-2 at (0,0), then 3 at (52,0) and 4 at (90,64) |
| `16` | cast list, then the game ends |
| `FF` | end; go back to the starting room |

During a scene the command box shows " Continue..." and WHAT ?.

**Visions** (verified; `story.cpp:367-440`, `story_scene.cpp:416-473`):

- **Queue:** at ds:1190, at most 10 entries. Nothing is queued until ds:0A bit 0 is set.
- **Delivery:** while Paul is idle in a room with something queued:
  - after 250 ms, the sender speaks it in person if present (character 16, list 4, ds:EA = the low byte of the id, speaker = high byte);
  - after 2,247 ms, it comes as a dream over VIS.HSQ frame 0.
- **First vision:** at phase 0x14, alone in the open desert, after 4,993 ms idle (WAIT FOR EVENING/MORNING counts):
  - set phase 0x15;
  - change byte 3 of Leto's record, Gurney's record and Harah's room;
  - set ds:D5 = 0xFF;
  - start the shipments;
  - set ds:0A |= 1;
  - queue vision 1.

**COMM room** (verified):

- **Messages** are words `(variant << 8) | person` at ds:1179, at most 10 (the oldest is dropped, duplicates ignored). ds:C8 is the count, ds:C9 the unread count, and bit 7 marks a message as seen.
- **Notice:** from phase 0x38, a new message while Paul is not in room 8 also queues vision 0x201.
- **Room 8 rows** appear only when there is at least one message:
  - VIEW NEW MESSAGES (202), greyed if nothing is unread;
  - Messages already seen (203), greyed if everything is unread.
- **The list** shows the senders, newest first, then "  Cancel" (150). Choosing one:
  - marks it seen;
  - sets ds:BF |= 0x20 if it is the Emperor's variant 2 or 3;
  - sets ds:24 = the variant;
  - shows the sender's list-4 line, with the rows " Viewed" (204) and WHAT ?.

### 2.7 The Emperor's spice shipments (#23)

Verified; `gameplay-rules.md`, `story.cpp:74-317`. Amounts are in 10 kg units.

- **Start** (at the first vision): the shipment day ds:118D = today (`time >> 4`), and the first demand is made immediately.
- **The demand**, with $n$ = the number of demands so far (ds:C3):

$$
D = \left\lfloor \frac{(150n+100)\,(r+224)}{256} \right\rfloor,\qquad r=\mathrm{rand} \mathbin{\&} 63
$$

  If the last shipment fell short (bit 7 of $f$ = ds:BE clear), raise it: $D \leftarrow \min\left(\mathtt{0xFFFF}, \lfloor D\,(256 + (255 - 2f \bmod 256))/256 \rfloor\right)$.

  Then ds:C3 + 1, ds:CF = 0, ds:BF |= 0x90, and post message 0x20B if bit 7 of ds:BE is set, else 0x30B.

- **Rating class** of $f$: count how many of 1, 0x40, 0x80, 0x90 and 0xFF are greater than $f$. The class runs from 0 (generous) to 5 (nothing shipped).
- **Period 3**, while shipments are running (ds:BF bit 7):
  - If ds:C2 is set, only update the days-left count.
  - While a demand is waiting, let `late = today - shipment day`.
    - Days 1-3: post reminder `table[late - 1][min(class, 2)] << 8 | 0x0B`, using `{4,5,6,0}`, `{5,6,0,0}`, `{6,0,0,0}`.
    - A 0 entry, or 4 days late: the Emperor ending (COMMAND 180).
  - If the unpaid flag (ds:11BB) is set, the game also ends.
  - Otherwise count down to the shipment day and make the next demand on that day.
- **Period 8:** queue vision 0x30B when a demand is waiting, Duncan is not with Paul, Paul is not in room 8, and ds:C2 is 0.
- **Duncan's offers (action 8)**, with stock $S$ and demand $D$:
  - Set ds:9F = 3 if $S > 0$, else 0. Set ds:1A = 0 and ds:20 = 0.
  - $\tfrac34 S$ means `(S >> 2) + (S >> 1)`.

  | Case | The four offers | ds:BF bits 1-2 |
  |---|---|---|
  | $S<D$ | $S$, $\tfrac34 S$, $\tfrac12 S$, $\tfrac34S-\tfrac12S$ | 0 |
  | $S<1.5D$ | $D$, $S$, $\tfrac34 S$, $\tfrac12 S$ | 2 |
  | $S<2D$ | $D$, $S$, $\tfrac34 S$, $1.5D$ | 4 |
  | otherwise | $D$, $S$, $1.5D$, $2D$ | 6 |

  He also brings up the smuggler with the oldest unpaid bill (`story.cpp:200-245`).
- **The menu (action 4):** each choice sets ds:9F and adds 1 to ds:1A.
- **Accepting (Duncan's action 9):** if ds:9F is below 2, the agreed amount ds:C0 = `offers[(ds:1A - 1) & 3]`, and ds:1158 = 0xFFFF.
- **Closing (Duncan's action 15):**
  - Before phase 0x10, set bit 0x10 of byte 0xFF7.
  - Otherwise end the talk, clear ds:C0, set ds:BF |= 1, and post message `((class + 7) << 8) | 0x0B`. Class 5 also sets the unpaid flag.
- **The shipment itself** happens on entering **room 8 with Duncan present** (bit 3 of ds:12) while an amount is agreed and armed.
  1. Pay `a = min(agreed, stock)`.
  2. $f=\max(1,\min(511, \lfloor 256a/D\rfloor)\gg 1)$.
  3. The next shipment day is 7 days later if $f \ge \mathtt{0xC0}$, 6 if above 0x80, 5 if exactly 0x80, and 4 if short. A second short shipment in a row sets ds:BE to 0.
  4. Add `rand & ((ds:C3 >> 1) & 3)` days.
  5. ds:BF = 0x80 plus 0x40 (generous), 0 (exact) or 8 (short).
- **Random numbers.** Swift's `randMasked` (`s * 0xE56D + 1`, returning the high product byte and the high state byte) matches the original `rand_masked`. ScummVM uses a different generator here, so keep Swift's.

### 2.8 Flat map, globe, map menu (#25 to #27)

- **The map picture.** MAP.HSQ is 50,681 bytes: the low 4 bits of each byte are terrain, bits 4-5 the ownership/vegetation stage, bit 6 marks a place. TABLAT.BIN is 99 rows of 8 bytes, each holding big-endian (offset, half-length).
- **The flat-map renderer** is dune-rust's `map_renderer.rs` (in Swift's `reference/dune-rust`), which `map.cpp:53-316` ports.
  - The view is 312 × 144 at (4,4): 36 bands of 4 pixels; band `i` shows row `lat + 80 + i`.
  - Each map byte becomes `((b & 15) << 1 | 1) << 3`, stretched to 4 pixels per cell and blended vertically.
  - The final colour is `(value >> 4) + 0x10` under ONMAP.HSQ's palette.
  - The row edges are masked with the 28-entry table at `map.cpp:223-251`.
- **Place positions on the flat map** (`map.cpp:284-316`).
  - A row has `len = 2 × half-length` cells.
  - The first visible column is `lng × len >> 16`, minus `len / 2` if `len` is below 88, else minus 44.
  - $x = 4 + \mathrm{out} + 4\,\mathrm{col} + 2 - 160$, where $\mathrm{out} = 140 - \mathrm{subpixel} + 2(88-\mathrm{len})^{+}$.
  - $y = 4 + 4\,\mathrm{band} + 2$.
- **Place positions on the globe:** $x = 160 + 4\lfloor 2\,\Delta\mathrm{lng}\,\mathrm{len}/2^{16}\rfloor$ and $y = 76 + 4(\mathrm{lat}-\mathrm{tilt})$. Draw a place only within a radius of 76 of the centre and when $\lvert\Delta \mathrm{lng}\rvert \le 12000$.
- **Scrolling:** longitude += `dx × 0x1002`, latitude += `dy × 12`, latitude kept within ±75. To centre on a place, set the view latitude to its latitude - 18.
- **Place icons:** ONMAP frame 122 + kind (0 sietch, 1 Atreides palace, 2 village, 3 fortress, 4 Harkonnen palace).
  - Skip hidden places, and keep a 320 × 152 index map so a tap finds the place.
  - Frame 127 is the "far sietch" icon; its distance threshold is not decoded.
  - Frames 58-70 are the troops' green ornithopters.
  - Frames 0x78/0x79 are vegetation tufts; use 0x79 when the cell to the east also sprouts.
  - SEE SPICE DENSITY draws rings with frame `133 + min(7, density / 32)` (scale guessed).
- **Around the map:**
  - four nested outlines starting at colour 0xFC;
  - the left panel is ICONES 6 with ICONES 0x0D (the planet) at (22,161);
  - during flights, ICONES 0x30 marks the position, 0x2F the trail (last 23 steps) and 0x2E the destination.
- **Arrow tap zones on the flat map:**

  | Arrow | Zone |
  |---|---|
  | up | (267,162)-(284,171) |
  | right | (285,171)-(297,184) |
  | down | (267,184)-(284,193) |
  | left | (254,171)-(266,184) |
  | centre | (266,171)-(285,184) |

  The globe's zones are the ones Swift already uses in `Fresk.swift:227-237`.
- **DUNE MAP popup** (verified). Shown only when the map is opened from a room.
  - Box (10,10)-(190,64), filled 0xFB, 1-pixel frame 0xF5.
  - COMMAND 213 in the small font at (20,18), 10-pixel lines, colour 243.
  - The number of rallied troops (ds:28) replaces the first number as a 3-character right-aligned field, capped at 999.
  - It closes on a tap or after 4,993 ms.
- **Map menu rows** (`scene.cpp:973-1000`):
  - EXIT MAPS.
  - GIVE ORDERS TO TROOP while the contact range is below 2 (greyed unless a hired troop is at Paul's place); otherwise CONTACT FREMEN TROOPS (greyed if none are rallied).
  - SEE SPICE DENSITY / STANDARD VISION, greyed before phase 5.
  - TAKE AN ORNITHOPTER, greyed if none is parked here.
  - FIND PROSPECTORS, from phase 5: centre on troop 3 and open its contact.
- **Choosing a destination.** Choosing a place (or a desert point) gives GO THERE FLYING AN ORNI or GO THERE RIDING A WORM. Once ds:0A bit 6 is set, a place's popup also offers the worm.
- **Head vs map.** Paul's head (tap zone (138,134)-(182,160)) opens the **globe** with the game menu; SEE DUNE MAP opens the **flat map**.

### 2.9 Travel, desert, arrival (#28, #30, #31)

Verified; `gameplay-rules.md` "Flight", `scene.cpp:398-486`, `:1302-1680`.

- **Distance in cells:** $\max(\lvert\Delta\mathrm{lng}\rvert\cdot\mathrm{cells}(\mathrm{lat}_0)/2^{16},\ \lvert\Delta\mathrm{lat}\rvert)$.
- **Speed:** one cell every **3,834 ms**; one game period passes every 16 cells. A tap or SKIP TO DESTINATION finishes the flight at once, still stopping for events. The rows during a flight are SKIP TO DESTINATION and CHANGE DESTINATION.
- **Leaving a place:** go to room 1, play the take-off, and remove one ornithopter from the place (byte 21 - 1).
- **Arriving:** discover the place, go to room 1, add one ornithopter (byte 21 + 1), play the landing, then run the room-entry lines (§2.5). A worm ride skips all the ornithopter steps.
- **Spotting places.** Only while someone travels with Paul. A findable place within 4 cells (hidden, and its phase byte is not 0xFF and is at most the current phase) offers GO TOWARDS THIS PLACE / RESUME FLIGHT (COMMAND 160 / 158).
- **Harkonnen zone** (ornithopter only, when the destination is not friendly; friendly = type below 0x28, or status bit 0x08):
  - The first step over a Harkonnen cell (stage 0x30) shows COMMAND 178 in a box from (6,6), fill 250, frame 243, with the rows RESUME FLIGHT and BACK TO STARTING POINT.
  - The 8th such step in a row shoots Paul down (ending COMMAND 175).
- **Arrival check** (`scene.cpp:1655-1678`), at a place in battle or not friendly:
  - if Fremen are attacking it (job 6) or its status has 0x02, Paul joins the battle (ds:2B = 1);
  - otherwise, if any Harkonnen troop is there, Paul is shot (ending COMMAND 177).
- **The open desert.** Flying to a desert point lands there (ds:8 = 0xFF).
  - The view is the sky, with (0,78)-(320,152) filled in colour 190.
  - Rows: SEE DUNE MAP; CALL A WORM (greyed before phase 0x4F); WAIT FOR EVENING (to period 12) before period 11, else WAIT FOR MORNING; TAKE AN ORNITHOPTER.
- **Flight view.** ScummVM's floppy flight view is adapted from Swift's own `Flight.swift` (`scene.cpp:1090-1152`), with a small map in (202,3)-(318,61). Swift can use `Flight.swift` directly.

### 2.10 Troops, spice, results (#32 to #34)

Verified; `gameplay-rules.md`, `world.cpp:829-1008`.

- **Fremen in a sietch** stand in **room 2**.
  - The place's first unhired troop is person 14.
  - The chiefs of its hired troops are persons 15, 16, and so on (names COMMAND 124-131).
  - Head and figure are `id % 3`. The idle expression is `id / 3`, reduced by 15 (for FRM1) or 17 (otherwise) until below that limit.
- **Charisma check.** It passes if any of these holds:
  - the Harkonnen men / 10 total is below 1000;
  - charisma is above 100;
  - $\lfloor(100-\mathrm{ch})/4\rfloor \le m$.
- **The motivation value $m$:** motivation, plus 20 if ds:FA is set. Then:
  - a troop attacking at Paul's place: $\min(m+30,100)$;
  - ecology jobs: 100;
  - any other job: $\min(m,100)$;
  - in phases 0x64-0x67: $\max(m-40,10)$.
- **Rallying a troop:**
  1. ds:28 + 1.
  2. Charisma + 1, capped at 200. Each multiple of 4 crossed raises every troop's motivation.
  3. Occupation = `(occupation & 0x20) | 2` (waiting for orders).
  4. Byte 0x0A = time, bytes 0x0C and 0x0E = 0, byte 0x14 = day.
  5. If the place's byte 11 is 0, set it to 2 and mark a disc of radius 2 as Atreides land.
- **Changing occupation** (`world.cpp:886-927`):
  - Write the whole occupation byte and clear speech bits 0x30.
  - For any job other than 2, set speech byte 0x13 |= `0x20 << (job >> 2)`.
  - Ecology (8) at place 62 with no bulbs becomes bulb growing (10).
  - Restart the job counters.
  - Jobs: 0 spice mining, 1 prospecting, 2 waiting, 4 military training, 5 espionage, 6 attacking, 8 irrigation, 9 wind trap, 10 bulb growing.
- **Troop contact popup** (from the map; `scene.cpp:1844-1986`):
  - A panel at (6,5), 230 × 67, fill 0xFB.
  - A 61 × 61 head box (fill 0xE4, frame 0xF5) showing a 59 × 59 crop of the FRM portrait. The crop points are (0x48,0x3D), (0x54,0x1D), (0x38,0x1A) for FRM1-3.
  - The chief's list-2 lines to the right.
  - Rows: ASK FOR MORE INFORMATION, SELECT/CHANGE TROOP OCCUPATION, MODIFY EQUIPMENT, MOVE TROOP, NO MORE ORDERS.
  - Occupation sub-menus as in `scene.cpp:1932-1972`. ECOLOGY is greyed until Kynes is met.
- **Troop data for the troop's lines:** ds:2C to ds:4B, plus name-table words 4-8 for the job, the duration and three ranks (`scene.cpp:1781-1829`).
- **Spice mining, each period.** It needs no stop bits, density of at least 1, and a place that is prospected and not exhausted (`(status ^ 0x40) & 0x41 == 0`).

$$
P = \big((m + (\mathrm{spiceSkill} \mathbin{\&} \mathtt{0xF0})) \bmod 256\big)\cdot \mathrm{pop},\quad P \leftarrow P/4 \text{ without a harvester},\quad \mathrm{kg} = \Big\lfloor \frac{((\mathrm{dens} \mathbin{\&} \mathtt{0xF0})+1)\cdot (\lfloor P/256\rfloor \bmod 256)}{128} \Big\rfloor \bmod 512
$$

  - The stock gains `(kg + carried remainder) / 10` units.
  - Density drops by `(kg + byte 19) / byte 17`, and the remainder is kept in byte 19.
  - Each time the troop's running total passes a multiple of 128 kg, its spice skill rises by 1.
- **Prospecting** takes `spice amount × 16 / max(1, motivation + spice skill)` periods. When done, set status 0x40, add 2 to the spice skill, and stop the job.
- **Results screen** (`scene.cpp:1689-1760`). The two FRESK panels slide apart by up to 100 pixels (frame 0 moves left, frame 1 starts at 214 and moves right). Texts:

  | Text | Position | Colour |
  |---|---|---|
  | "Nth day on DUNE" | (16,6) | 0xFD |
  | "CHARISMA = n" | (216,6) | 0xFD |
  | area %, Harkonnen / Atreides | (20,69) / (48,69) | 0x3F / 0x25 |
  | CONTROLLED AREAS | (8,80) | 0xFB |
  | spice, Harkonnen / Atreides | (240,60) / (272,60) | 0x3F / 0x25 |
  | SPICE PRODUCTION | (236,71) | 0xFB |
  | men, Harkonnen / Atreides | (240,131) / (272,131) | 0x3F / 0x25 |
  | NUMBER OF MEN | (236,142) | 0xFB |
  | ATREIDES | (35,125) | 0x25 |
  | HARKONNENS | (35,139) | 0x3F |

  - Areas are counted over map cells 0x188 to 0xC5F9: stage 0x30 is Harkonnen, any other non-zero stage is Atreides (and the Atreides figure gets + 1).
  - Spice: Harkonnen = ds:A8, Atreides = ds:A6.
  - Men: the Harkonnen total, and the total of troops whose `occupation & 0xA0` is 0; printed with a trailing "0".
  - Six bars of ICONES 0x37 (Harkonnen) or 0x38 (Atreides), capped by 0x39, at most 30 high, at (26,62), (54,62), (252,54), (280,54), (252,125), (280,125).
  - Bar heights: area / 2 + 1, spice >> 4 + 1, men >> 8 + 1.

### 2.11 Ecology (#35)

Verified; `gameplay-rules.md` "Ecology", `ecology.cpp`.

- **Wind trap (job 9).** Each period motivation rises by 1 (max 100) and location byte 27 gains $\max(1, \lfloor \min(255, 2m + \mathrm{spiceSkill}) \cdot \mathrm{pop} / 4096\rfloor)$ (the code reads troop byte 0x16). When byte 27 passes 255:
  - status |= 0x20 and type |= 8;
  - water = 5;
  - the troop goes back to irrigation.
- **Bulb growing (job 10, place 62 only).** ds:EC counts up by 1 each period. When it wraps to 0, location byte 26 = 16 and the troop switches to irrigation.
- **Irrigation (job 8).** Needs water of at least 1, a wind trap, and bulbs carried by the troop.
  - First period: status |= 1, density = 0, disc centred on the place with radius 4, ds:FA = 1, then spread.
  - Later periods: progress (byte 15) += `max(1, ecology skill >> 2)`. On overflow:
    1. ecology skill + 1;
    2. water - 12 (or stop if there is not enough);
    3. radius + 1, up to 12;
    4. move the centre 2 rows north, not past -82;
    5. spread.
- **Spreading the disc** (latitude limit ±0x56). For each cell that is not already sprouting:
  - set its stage to 0x20 (Atreides land);
  - for sand cells (`terrain & 0x0E` below 8), rotate a mask that starts at 0x44; when a bit falls out, make the cell sprout (stage 0x10);
  - if the cell is a place, it loses its spice, and a hostile place other than the two palaces falls.
- **Each new day:**
  1. Behind each wind trap, water += 1 + half the sprouting cells among the 6 map bytes around the place, up to 250.
  2. Walk 0x46 steps of a shift register (state starts at 1 and is not saved): `s >>= 1`, XOR with 0x402 when the bit shifted out was 1.
  3. At each step, turn sprouting cells at offsets `s`, `s + 0x7FF`, ... (below 0xC5F9) into stage 0x20.

### 2.12 Marches, battles, worms, final attack (#36)

Port directly from `battle-worm-spec.md` §1-§6. In short:

- **Random numbers:** `rand` is $s \leftarrow \mathtt{0xCBD1}\,s+1$ and `rand_masked` is $s \leftarrow \mathtt{0xE56D}\,s+1$. Neither is saved; both are seeded from the clock.
- **Marches:** 7 steps when ordered, then 4 per period (8 with an ornithopter). A troop has arrived when the larger gap is below 7 cells.
- **Strength:** $S=\min(255,\lfloor bM/256\rfloor)$ with $b=\lfloor \min(255,2m+a)\,p/16\rfloor$ and $M=1+2k+4l+8w+16t$. Here $k$, $l$, $w$, $t$ are 1 if the troop has krys knives, laser guns, weirding modules, atomics.
- **Balance:** $\min(252,\lfloor 128F/H\rfloor)$ when $F\ge H$, otherwise $256-\min(252,\lfloor128H/F\rfloor)$.
- **Loss** inflicted on a troop with army skill $a$: $\min(p,\lfloor x(255-2a)/256\rfloor)$. The byte arithmetic wraps when $a > 127$.
- **Battle rounds:**
  - normally one roll per attacking troop per period;
  - MASSIVE ATTACK: one roll repeated up to 16 times, with no time passing;
  - FIGHT FOR A WHOLE DAY: up to 16 periods.
- **A fort won** (spec §3.7):
  - Atreides land around it;
  - charisma + 4;
  - its equipment becomes free stock;
  - it becomes a sietch two days later.
- **Worms:**
  - CALL A WORM is greyed before phase 0x4F; the first ride sets phase 0x50;
  - no ornithopter is used, there is no Harkonnen-zone check, and calling a worm ends a battle;
  - the floppy has no VER.HNM: use VER.HSQ, WORMSUIT.HSQ and Swift's `WormRide.swift`.
- **Final attack:** the ds:C2 stages and the 10,000-men test at locations 2-4 (spec §6.2). When the palace falls, every Harkonnen cell (0x30) becomes Atreides (0x20).

### 2.13 Saves (#38, #39)

Verified; (checked today) against the 5 saves shipped in `DuneFiles/`.

- **Header:** time (u16), then `0x02F7` (the low byte 0xF7 is the RLE marker), then file length - 2 (u16).
- **Compression:** the byte 0xF7 is followed by a count and a value. When saving, write runs longer than 2, and every 0xF7 byte, that way.
- **Unpacked body = 22,051 bytes:**

  | Part | Bytes |
  |---|---|
  | map stage bits, 4 pixels per byte, first pixel in the top 2 bits | 12,671 (0x317F) |
  | an extra block of the executable's own (keep it from the last load, else zeros) | 198 |
  | DIALOGUE.HSQ with its said flags | 4,464 |
  | the data segment `vars[0 ..< 0x126E]` | 4,718 |

- **After loading:**
  1. Put the stage bits back into each map cell: `(cell & 0xCF) | bits << 4`.
  2. Set bit 6 again on every place's cell.
  3. Rebuild the book's journal from the said lines that have a topic.
- **Slots:** 0 "Log 1", 1 "Log 2", 2 "LAST ENTERING INTO A PLACE", 3 "LAST ENTERING NEW SIETCH". (guessed) When the original writes slots 2 and 3 automatically is not documented.
- **The shipped saves.** `DUNE21S0.SAV` is at time 2, the new-game state. `DUNE21S1` to `DUNE21S4` (times 49, 46, 57, 29) are mid-game states that can be loaded for testing before anything else works.
- **Menu rows:**
  - Globe menu: EXIT GLOBE (170), SEE RESULTS / STANDARD VISION (164 / 165), SAVE GAME (166), LOAD GAME (167), OPTIONS & QUIT GAME (168).
  - Save/load list: the 4 slots, then EXIT GLOBE; afterwards " SAVE SUCCESSFUL" (262) or " *** SAVE ERROR " (263).
  - Options: MUSIC OFF or MUSIC ON (GAME RELATIVE) (257 / 254), RESTART GAME (173), EXIT GAME (174), EXIT GLOBE.
  - Quit confirmation: 171 / 172.

### 2.14 Mirror, endings, music (#40, #41, #43)

- **Mirror** (verified; `scene.cpp:1253-1300`). Draw:
  1. MIRROR.HSQ frame 1;
  2. Paul's face: PAUL.HSQ animation `min(time >> 6, 8) × 2`, frame 0, at (86,0);
  3. MIRROR frame 2 on top.

  The rows are RESTART, LOAD, SAVE, EXIT GAME and "Look away from the mirror" (146). The clock stops.
- **Endings** use COMMAND 175-180:

  | COMMAND | Ending |
  |---|---|
  | 175 | shot down |
  | 176 | Water of Life |
  | 177 | shot on arrival |
  | 179 | captured in battle |
  | 180 | the Emperor |

  The final credits are COMMAND 277-289.
- **Music per place.** Neither engine knows it. The original picks among SIETCHM, WATER, WARSONG, MORNING, WORMSUIT (for the worm) and BAGDAD, but that table has not been decoded. This is research, not a port.

---

## 3. Porting order

Five milestones of a few hours each. Earlier ones are needed by later ones, and each ends in something playable.

**Milestone 1: world data and a correct palace**

1. LZEXE unpacking and `GameState.vars` (0x1500 bytes) with byte and word accessors and the floppy offset conversion (§2.1). Find the tables by searching, as ScummVM does.
2. Location, character, troop and room records; room tables; sheet slots; `.SAL` file by type (§2.2).
3. Remove the hard-coded palace exits, the room-to-`.SAL` list and the sheet ranges in `Scenery`. Implement locked doors, and exits 252-254 as "leave" (a stub until the map exists).
4. People in the room from the character table, with the marker rule. Remove `palaceRoomMarkers`.
5. Clock fixes (§2.3):
   - start at time 2 and use the right day formula;
   - pause outside rooms and maps;
   - sun and moon from the period table;
   - sky palette per period;
   - large vs narrow sky and BALCON frame 2 for the palace's outdoor rooms.
6. Text-code expansion (§2.4); stop dropping `.`.
7. Optional: a read-only `DUNE21S` loader, so later milestones can be tested from the shipped saves.

**Milestone 2: the dialogue engine and the story**

1. CONDIT evaluator; DIALOGUE with the PHRASE11/12 split; the conversation walk; said flags; the book's journal (§2.5).
2. Talk verbs and companions, with companion icons on the panel.
3. Actions 1, 2, 6, 7, 11, 12, 14; setting the phase; phase triggers (run twice at new game); the phase-callback table (§2.6).
4. Lines on entering a room, and place data for conditions.
5. Scripted scenes read from the executable, " Continue...", CHANKISS.
6. The book built from the dialogue data.
7. The talk screen: portraits (reuse `Character.swift`), the speech balloon (ICONES 0x1C) and the zoom on the speaker.

This gives the real opening, driven by the data: Leto's three lines, Jessica, Duncan arriving at phase 1, the stillsuits, and the COMM doors at phase 0x0C.

**Milestone 3: map, travel and other places**

1. The flat map (port `map_renderer.rs`), icons, taps, arrows, the DUNE MAP popup and the map menu (§2.8).
2. Icons on the globe; Paul's head opens the globe and SEE DUNE MAP the flat map.
3. The flight loop, reusing `Flight.swift`, with ornithopter take-off and landing (§2.9).
4. Sietch, village and fortress rooms from the tables; the outdoor rooms; Fremen in sietch room 2.
5. Arrival rules: discovery, being shot on arrival, companions spotting places, the Harkonnen zone.
6. The open desert, visions, the first vision, and the VIS dream.

**Milestone 4: troops, spice, shipments, saves**

1. WORK FOR ME and the charisma check; rallying; CONTACT and GIVE ORDERS; the troop popup; occupations (§2.10).
2. Jobs each period: mining and prospecting; Harkonnen growth and production; FIND PROSPECTORS; SEE SPICE DENSITY.
3. The whole shipment cycle and the real COMM room (§2.6, §2.7).
4. The results screen with real figures.
5. Saving and loading in DOS format; the options menu; restart; the mirror.

**Milestone 5: ecology and war**

1. MODIFY EQUIPMENT, ecology jobs, vegetation, forts falling, and tufts on the map (§2.11).
2. From battle-worm-spec: marches and MOVE TROOP, espionage, battles (the night-attack picture can reuse `Attack.swift`), the captain, forts becoming sietches, worms, the final attack, the ending and credits.
3. Stretch goals (ScummVM does not have them either): Harkonnen raids (spec §5, fully specified), smugglers' trade, and the music table.

---

## 4. SwiftDune bugs and shortcuts that contradict FINDINGS or the data

1. **Palace exits are misread** (`Game/Scenes/Game.swift:1039-1047`, `:492-500`).
   - Exit values 0x8C, 0x8B, 0x88, 0x87 and 0x83 are **locked doors** to palace rooms 12, 11, 8, 7 and 3.
   - Swift treats them as desert exits. `showDesert` sets `currentLocation = exit & 0x7F`, which is how room 2's left exit "reaches" location 12 (Carthag-Tuek).
   - Room 1's real exit 253 (leave the place) is ignored.
   - Arrows are shown for locked doors.
2. **Leto stands on the wrong marker** (`Game.swift:39`, `:55-58`; `Engine/Resources/Scenery.swift:314-329`). Swift puts him on marker 0. FINDINGS (verified against a recording) says the slots map onto the markers from the last one down, so he stands on the last marker at (186,53). Jessica's `[7: .jessica]` is likewise a guess.
3. **Greenhouse uses the wrong sheet** (`Scenery.swift:149-152`).
   - The comment says code 0xCF means PALPLAN. But room code 207 = 0xCF gives slot `(207 - 1) >> 4 = 0xC`, which is **SERRE** in the verified slot table; PALPLAN is slot 0xE.
   - If SERRE looked corrupted in Swift, the likely cause is the palette order (panel, then sheet, then colour 0 black), not the sheet.
4. **Palace front sky** (`Game/Scenes/Palace.swift:165-172`).
   - Room 1 (`.SAL` room 11) is drawn with the narrow sky across 320 pixels. It should use the large sky, 200 pixels wide.
   - BALCON frame 2 is missing underneath.
   - In play the sky is always daytime.
5. **Clock** (`Game/GameTypes.swift:307-360`, `Game.swift:513-516`).
   - It starts at time 0 instead of 2.
   - The day is shown as `t/16 + 1` instead of `((t+3) >> 4) % 365 + 1`.
   - The four "phases" split the day into quarters of 4 periods; they match neither the sun/moon table nor the time labels.
   - The clock keeps running during talks and menus.
   - The sun or moon is drawn at one fixed spot (`UI.swift:182-183`).
6. **Text** (`Engine/Resources/Sentence.swift:57-59`).
   - `printableOnly` removes every `.` (0x2E), so dialogue lines lose their full stops.
   - No text codes are expanded: nested lines, names and numbers show as garbage, and page breaks are ignored.
7. **Dialogue is not the game's engine** (`Game.swift:322-351`). It shows fixed PHRASE11 lines chosen by invented rules. Lines from the sixth character on (DIALOGUE offset 0x920 and later) are in **PHRASE12**. So Swift's numbers for Stilgar, Kynes, Chani, Harah and the Fremen (294, 432, 174, 309, 326 in PHRASE11) are very likely other characters' lines.
8. **Invented story progress.** In the original, the phase changes only through dialogue actions 11/12, the callbacks, discoveries, rallying and the worm. Swift instead:
   - moves to phase 1 when talking to Leto or Jessica (`Game.swift:457-461`);
   - moves to phase 1 on landing at location 12 (`:201-204`);
   - moves to phase 5 in `findProspectors()` (`GameTypes.swift:404-409`), whereas in the original phase 5 is what *enables* FIND PROSPECTORS;
   - also moves to phase 5 when SPICE is chosen (`GameTypes.swift:384-388`).
9. **Wrong prospector place** (`GameTypes.swift:278`, `:321`). `prospectorLocation = 2` is labelled "Carthag-Timin", but location 2 is an Arrakeen fortress (checked today). The prospectors are troop 3 at location 11.
10. **Shipments** (`GameTypes.swift:362-371`, `:411-519`; `Game.swift:543-559`, `:706-718`).
    - The first demand is rolled on a later day change or when talking to Duncan, not at the first vision.
    - "4 days remaining" is invented. There are no reminders, no Emperor ending and no shortfall increase.
    - Spice is shipped without Duncan being in room 8. No rating or next shipment day is computed.
    - ACCEPT, REFUSE and ARGUE take effect directly instead of through Duncan's lines.
11. **COMM room** (`Game.swift:258-265`, `:1005-1009`). The comment says COMMAND1 lacks the COMM rows; it does not (202, 203, 150, 204). The original also shows these rows only when there are messages, and lists the real senders.
12. **Results screen** (`Game/Scenes/Fresk.swift:179-210`).
    - It prints the templates COMMAND 181-191 ("  2nd day on DUNE", "CHARISMA = 129", ...) as they are.
    - It also prints **COMMAND 192, "Insufficient STANDARD MEMORY to run DUNE"**.
    - A debug overlay is drawn on top.
13. **Globe and map** (`Game.swift:861-862`; `Fresk.swift:257-260`).
    - SEE DUNE MAP opens the globe instead of the flat map.
    - OPTIONS jumps straight to the quit confirmation.
    - SAVE and LOAD do nothing.
14. **Sietch** (`Game.swift:196-237`, `Game/Scenes/Sietch.swift:55-65`).
    - Every sietch shows `.SAL` room 8 with the intro's cast. In play, room 1 is the SIET0 outdoor view and the Fremen stand in room 2.
    - Row 124 is used as "Fremen", but 124 is "Fremen Chief"; "Fremen" is 123.
    - The hiring verb should be WORK FOR ME (139).
15. **Invented troop model** (`GameTypes.swift:171-201`, `:374-389`). The global `TroopOrder` (HOLD / ADVANCE / HARVEST / REGROUP) and occupation do not exist in the game. Occupations belong to each troop record.
16. **Desert walk** (`Game/Scenes/DesertWalk.swift:118-130`). The arrow keys step a counter over a fixed picture. The original desert is reached only by flying to a desert point, and offers WAIT, CALL A WORM and TAKE AN ORNITHOPTER.
17. **Who is in each palace room is hard-coded by phase** (`Game.swift:258-280`): Gurney in the throne room, Duncan in room 4, Thufir in room 8. The original moves people through their records. Duncan does reach room 4 at phase 1, but that match is a coincidence.
18. **Panel details** (`UI.swift:137-140`; `Game.swift:826-829`).
    - The companion boxes always show the empty icon 64 instead of `0x41 + id`.
    - The book opens on a tap anywhere with x below 90, instead of the original zone (24,155)-(69,176).
    - Rows cannot be greyed.
19. **The spice-density list** (`GameTypes.swift:232-247`) duplicates data that is in the executable and is not enough for mining, which also needs the spice field and amount computed at new game (§2.1).
20. **Where Swift is more exact than ScummVM.** Swift's `randMasked` matches the original generator, and its 12,001-tick period is a plausible reading of the timer code. Keep both.
