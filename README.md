# squid

### A generative, clock-locked sampler for Monome Norns

squid is an eight-slot sampler for Monome Norns, built in the spirit of the
[ALM Squid Salmple](https://busycircuits.com/pages/alm022). It records from the inputs and replays what it captures on its
own terms: each of the eight slots is permanently bound to a random effect, each
runs its own clock-synced loop, and each playback is scattered across the stereo
field and the spectrum before passing through a fixed lo-fi colour. You never
choose which effect lives where. You tune a handful of knobs; squid does the
rest.

Plug audio into the inputs. squid samples live in only.

The character is emergent. At launch each slot draws one of eight effects, used
once each, and the GUI shows the assignment. Every time a slot plays, that fixed effect
is stacked with a fresh random bandpass and stereo position, then run through the
crunch that sits on the playback bus. Randomize reshuffles which effect
lives on which slot. squid is purely rhythmic — it does nothing without a running
clock — and it starts silent: raise record and play probability to bring it to
life. Or take the wheel — per-slot faders, mutes, and manual play/record triggers
let you play squid as an instrument over its own generative churn.

## What it does

**Slots.** Eight stereo slots, up to 8 seconds each. A slot is empty until a
record trigger captures into it; once filled it can be overdubbed, played, or
cleared, but its length and content persist until you clear all buffers.

**Effects.** At launch, and again on every Randomize, the eight effects are dealt
one-to-one across the slots: **pitch −12** and **pitch +12** (an octave down and
up, length preserved), **half speed** and **double speed** (rate and pitch
together), **forward** and **reverse**, **low cut** and **high cut** (high- and
low-pass around 250 Hz). Each is used exactly once. The current assignment is shown in the GUI's effect
row (see Screen).

**Triggering.** Each slot runs its own loop, independent of the others. Divisions
are drawn from ten steps spanning a 1/64 note to eight bars (0.0625–32 beats), and
the slot waits for one on the Norns clock, so the eight slots drift in and out of
phase with each other. Two options shape this: **division decision** picks whether
each slot re-rolls its division on every trigger (the default, fully shifting) or
holds one division per slot until you Randomize — in which case the eight slots
take eight *distinct* divisions (more groove-like); **division skew** weights the
draw toward the fast end (short), the slow end (long), or evenly (full range,
default). It biases the odds without ever excluding the far end, so a
long-skewed slot can still occasionally fire fast.

**Probability.** At each trigger, play is rolled first and wins over record. If
play does not fire, record is rolled: an empty slot records fresh, a filled slot
overdubs. The recorded length is the current division, capped at the 8-second
buffer. Playing an empty slot returns silence — no fallback, no skip.

**Record shield.** A latch that freezes buffers against recording and overdub
while slots keep playing. There is a **global** shield (K2) and a **per-slot**
shield; a slot is protected if either is engaged. The per-slot shield shows as a
dimmed frame around that slot's status glyph on screen.

**Spatial scatter.** Inspired by the [ALM Jumble Henge](https://busycircuits.com/pages/alm029). Each slot is assigned one
cell of a **three-band by five-position** matrix: a bandpass (20–499, 500–1999, or
2000–9999 Hz) and a stereo balance (hard left, mid left, centre, mid right, hard
right). The assignment is **unique per slot** — no two slots share a cell — and is
fixed until you Randomize, which re-deals it alongside the effects. It stacks on
top of the slot's effect, so a band that fights the slot's own filter occasionally
lands near-silent — by design. The matrix is drawn top right and each cell lights
while its slot plays (see Screen).

**Sample shape.** Two global controls — **sample attack** and **sample decay** —
fade each played voice in and out. They are set as a fraction of that voice's play
length, so the fade scales with the loop's division: 0 % is the hard, clicky gate
(the default), higher values smooth the onset and tail. At the extremes the
envelope becomes a triangle peaking mid-loop.

**Resample.** Output folded back to input. With **resample** on and **resample
amount** up, the currently-playing loops are mixed into the record source, so new
takes capture them — loops recirculate and layer over generations. The feedback
is one block delayed so the loop stays stable.

**Crunch.** A lo-fi colour on the slot-playback bus — sample-rate reduction,
bit-quantize, and a little noise. Only the sampled voices wear the grit. It is inspired by 12-bit hardware samplers like
the [Akai S900 and S950](https://en.wikipedia.org/wiki/Akai_S900) — where the
character comes from the converters, the anti-alias filtering, and rate-based
aliasing — but it is a loose evocation, not an exact emulation. Adjust it with the **crunch amount** parameter: the default is the
original baked-in colour, 0 is near-clean, 100 is heavy.

**Per-slot mixing.** Each slot has its own **level** fader and a **mute**. Level
sets the slot's playback gain ahead of the global output; mute silences that slot
alone while its loop and any recording keep running (mute is not a record shield).
Both act immediately and continuously — muting or riding a fader affects even a
one-shot already sounding. On screen each slot shows a fader: a bright frame when
active, dimmed when muted, the handle at the current level. A **global mute** and
a **mute flip** act on all eight at once.

**Manual control.** Alongside the probability loops, every slot can be played or
recorded by hand — one trigger per slot for **play** and one for **record**,
independent of the play/record odds. A **manual quantize** option fires them
immediately (free) or on the slot's next division (quantized). Manual record
honours the shields and captures for the slot's current division, exactly like the
probabilistic path.

**Randomize.** Re-rolls the effect-to-slot assignment without touching the
buffers. The per-slot divisions are random on every trigger anyway, so a single
key reshuffles the whole character while your loops keep playing.

## Signal flow

```
                      audio IN
                          │
                  record / overdub
                          │
                    slot buffers
                          │
                        play
                          │
                     slot effect
                          │
                 bandpass + balance
                          │
                   attack / decay
                          │
              per-slot level / mute
                          │
                    8-slot sum
                          │
                       crunch
                          │
                     master gain
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
     OUT L/R           ~sendA            ~sendB
```

squid outputs only its sampled voices — the live input itself is not monitored
through the script. Record and overdub capture from the input (and, with resample
up, fold the playing loops back in). Play routes a slot through its fixed effect,
then its scatter cell, then its attack/decay envelope, then the per-slot level and
mute. The eight slots sum, pass through the shared crunch, and output volume scales
the whole mix. If you want to hear the live signal alongside the loops, enable
Norns' system input monitor.

squid also works with fx mods: its output is mirrored to the fx-mod send buses, so
it can act as a stereo source for them. Enable the mod (mods load before scripts,
so it must be active when squid loads) and squid feeds its sends automatically;
with no mod active there is no send and no overhead.

## Controls

| Control | Function |
|---------|----------|
| **E1** | Output volume |
| **E2** | Record probability |
| **E3** | Play probability |
| **K1 hold 2s** | Clear all slot buffers |
| **K2** | Record shield — toggle; slots keep playing but are never recorded over |
| **K3** | Randomize — re-roll the effect-to-slot assignment |

A short tap of K1 is reserved by Norns for its menu, so clearing the buffers
requires a hold. Everything per-slot — level, mute, manual play/record and the
per-slot shield — lives in PARAMS and maps to MIDI (see Parameters); the front
panel stays a three-knob, three-key overview.

## Screen

The screen is a single panel, centred. Everything sits at low brightness until a
state lifts it to full.

**Header.**

- **Record shield**, top left. Full brightness while the global shield is engaged.
- **Input meter**, the two columns below the shield — the live left and right
  input levels, body dim with a bright peak cap, ballistics tuned to the tempo.
- **Output / record / play bars**, top centre. Each fills pixel by pixel with its
  value.
- **Mixer matrix**, top right — the three-band by five-position scatter grid, drawn
  dim. A cell lights to full while the slot routed there is playing, so you can see
  where the output is landing across the spectrum and stereo field.

**Slot columns.** The eight slots, left to right, each a stack of four cells:

- **Status** — **P** playing, **R** recording, an angle for a filled idle slot,
  **X** empty (P and R at full brightness). The frame around this cell is bright
  when the slot can record, dimmed when its record shield is on.
- **Effect** — the effect currently assigned to the slot; reshuffles on Randomize.
- **Fader** — the per-slot level (handle height) and mute (bright frame active, dim
  frame muted).
- **Number** — the slot's number, 1–8.

## Parameters

The PARAMS menu is split into a **global** group and eight **slot** groups. All
parameters are MIDI-mappable.

**global**

| Parameter | Default | Range |
|-----------|---------|-------|
| output volume | 50 % | 0–100 % |
| record probability | 0 % | 0–100 % |
| play probability | 0 % | 0–100 % |
| division decision | on play | on play / on randomize |
| division skew | full range | short / long / full range |
| sample attack | 0 % | 0–100 % |
| sample decay | 0 % | 0–100 % |
| resample | no | no / yes |
| resample amount | 0 % | 0–100 % |
| crunch amount | 25 % | 0–100 % |
| manual quantize | free | free / quantized |
| t: clear | — | trigger |
| t: shield | — | trigger |
| t: randomize | — | trigger |
| t: global mute | — | trigger |
| t: global mute flip | — | trigger |

**slot 1 … slot 8** (each)

| Parameter | Default | Range |
|-----------|---------|-------|
| level s# | 100 % | 0–100 % |
| t: mute s# | — | trigger |
| t: play s# | — | trigger |
| t: rec s# | — | trigger |
| t: record shield s# | — | trigger |

Output volume, record probability and play probability mirror the three encoders
(E1/E2/E3). Record and play default to 0 % so squid starts silent and waits for
you. Sample attack/decay are a fraction of each voice's play length. Crunch
defaults to the original baked-in colour (0 % near-clean, 100 % heavy). Every
trigger fires on a CC ≥ 64 — the global three mirror K1/K2/K3, and the per-slot
play, record, mute and shield map cleanly to pads for hands-on control.

## Synchronization

squid is locked to the Norns clock (internal or MIDI) and does nothing without
one. Each slot's per-trigger division is converted to beats:

| Division | beats |
|---|---|
| `8/1` | 32 |
| `4/1` | 16 |
| `2/1` | 8 |
| `1/1` | 4 |
| `1/2` | 2 |
| `1/4` | 1 |
| `1/8` | 0.5 |
| `1/16` | 0.25 |
| `1/32` | 0.125 |
| `1/64` | 0.0625 |

`1/1` is one bar (4 beats). The slot waits that many beats on the clock before
firing, and a record captures for the same length — `beats × 60 / BPM` seconds,
capped at the 8-second buffer. Stop the clock and squid stops.

## MIDI

All parameters are available in the PARAMS menu and can be mapped to any MIDI CC
using Norns' built-in MIDI learn.

1. Open the PARAMS menu and scroll to the parameter.
2. Press K3 to enter MIDI learn mode (the entry flashes).
3. Send a CC from your controller.

The mapping is saved with your PSET. All MIDI input is on channel 1 by default;
change the channel in PARAMS > MIDI. The Norns clock can also be driven from MIDI
via PARAMS > CLOCK > SOURCE.

## Install

Via Maiden: open `http://norns.local/maiden` and run:

```
;install https://github.com/notrobintaylor/squid
```

Or via SSH:

```bash
ssh we@norns.local
cd ~/dust/code
git clone https://github.com/notrobintaylor/squid
```
