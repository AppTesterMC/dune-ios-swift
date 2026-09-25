# TODO

## Current

- [ ] ADD: scripted character animations as a sequence of indexes
- [ ] UPDATE: separate globe node for foreground rendering

# Roadmap

## Scenes

- [ ] ADD: Ornithopter flight animated dunes
- [ ] ADD: flat planet map with interpolation (ported, not yet checked on screen)
- [ ] UPDATE: improve sun rise animation

## Engine

- [ ] ADD: create an asset cache and preload all resources for faster access
- [ ] UPDATE: node params as property wrappers ?
- [ ] UPDATE: rewrite editor to properly use node system and engine

## Animations

- [ ] UPDATE: new animation system on Stars planet pan
- [ ] ADD: Page flip transition on frame buffer
- [ ] ADD: Move up transition on frame buffer
- [ ] ADD: Wobble effect on frame buffer (visions)

## Video

- [ ] FIX: overlay circles and logo in last frames

## UI 

- [ ] ADD: dialogue panel background on characters
- [ ] UPDATE: menu states (selected, disabled) (selected done; greyed rows missing)
- [X] ADD: implement UI sun/moon and day number (ds:1E7E positions, sky per period)
- [X] ADD: implement UI bar characters going with Paul (companion slots ds:1152/1153)
- [X] ADD: globe settings (SAVE, LOAD, OPTIONS: music, restart, exit)
- [ ] ADD: interpolated flat map (ported, not yet checked on screen)

## Game logic

- [ ] ADD: dialogue panels (dialogue engine done; speech balloon still missing)
- [X] ADD: implement day timer (Game/World, runPeriod each period)
- [ ] ADD: sietch positions on map (ported, not yet checked on screen)
- [X] ADD: implement global game variables (the executable's data segment, Game/World/World.swift)
- [X] ADD: implement save file format (DUNE21S, Game/World/SaveGame.swift)
- [X] ADD: support string formatting in sentences (Game/World/GameText.swift)
- [X] ADD: reverse engineer CONDIT.HSQ (ported from the ScummVM engine)
- [X] ADD: reverse engineer DIALOGUE.HSQ (ported from the ScummVM engine)

## Platform

- [ ] FIX: high memory consumption from Metal renderer
- [ ] ADD: support Swift 6: CustomDebugStringConvertible and @DebugDescription, 
- [ ] ADD: support different versions of Dune (detect Savegame) (floppy/CD detected from the executable; CD not playable)
- [ ] ADD: extend port to Linux and Windows
- [X] ADD: iOS port (IOS_PORT.md)
- [ ] ADD: support PC-CD versions

# Archive

- [X] ADD: support for OPL3

- [X] ADD: animated night attack scene w/ flash
- [X] ADD: Reverse engineer animation for ATTACK

- [X] FIX: Fade in Dune title (palette effect)
- [X] FIX: Fade in on Palace stairs (palette effect)
- [X] ADD: call a worm animation
- [X] ADD: Reverse engineer animations for SHAI
- [X] ADD: Reverse engineer animation for DEATH
- [X] ADD: Handle mouse click events
- [X] ADD: support gradients on polygons

- [X] FIX: Globe/Stars palette on prologue
- [X] ADD: Reverse engineer animation for VER
- [X] UPDATE: fade in/out on prologue (Palace stairs)
- [X] UPDATE: new animation system on Baron sardaukar
- [X] UPDATE: implement sky as node everywhere
- [X] ADD: copy protection screen
- [X] FIX: video PRT.HNM cannot be read
- [X] UPDATE: Sprite rendering issue on DUNES
- [X] ADD: create Character node for characters in foreground
- [X] UPDATE: Separate foreground/background nodes (characters vs. layout)
- [X] FIX: y-offset on pixel dissolve animation 
- [X] UPDATE: separate ornithopter from background
