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
life.

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

**Triggering.** Each slot runs its own loop, independent of the others. At every
trigger the slot re-rolls a division from {4/1, 2/1, 1/1, 1/2, 1/4, 1/8, 1/16,
1/32} and waits for it on the Norns clock, so the eight slots drift in and out of
phase with each other. Two options shape this: **division decision** picks
whether each slot re-rolls its division on every trigger (the default, fully
shifting) or holds one division per slot until you Randomize (more groove-like);
**division skew** restricts the pool to short (1/2–1/32), long (4/1–1/1), or the
full range (default).

**Probability.** At each trigger, play is rolled first and wins over record. If
play does not fire, record is rolled: an empty slot records fresh, a filled slot
overdubs. The recorded length is the current division, capped at the 8-second
buffer. Playing an empty slot returns silence — no fallback, no skip.

**Record shield.** A global latch. While engaged, slots keep playing but are
never recorded into or overdubbed — the buffers are frozen as they are.

**Spatial scatter.** Inspired by the [ALM Jumble Henge](https://busycircuits.com/pages/alm029). Every playback draws a
cell from a four-band by five-position matrix: a bandpass (20–249, 250–999,
1000–2499, or 2500–9999 Hz) and a stereo balance (hard left, slight left, centre,
slight right, hard right). The cell is fixed for the duration of that play and
re-rolled on the next. It stacks on top of the slot's effect, so a band that
fights the slot's own filter occasionally lands near-silent — by design.

**Sample shape.** Two global controls — **sample attack** and **sample decay** —
fade each played voice in and out. They are set as a fraction of that voice's play
length, so the fade scales with the loop's division: 0 % is the hard, clicky gate
(the default), higher values smooth the onset and tail. At the extremes the
envelope becomes a triangle peaking mid-loop.

**Resample.** Output folded back to input. With **resample** on and **resample
amount** up, the currently-playing loops are mixed into the record source, so new
takes capture them — loops recirculate and layer over generations. The live dry
path stays clean; the feedback is one block delayed so the loop stays stable.

**Crunch.** A lo-fi colour on the slot-playback bus — sample-rate reduction,
bit-quantize, and a little noise. The live input passes through clean; only the
sampled voices wear the grit. It is inspired by 12-bit hardware samplers like
the [Akai S900 and S950](https://en.wikipedia.org/wiki/Akai_S900) — where the
character comes from the converters, the anti-alias filtering, and rate-based
aliasing — but it is a loose evocation, not an exact emulation. Adjust it with the **crunch amount** parameter: the default is the
original baked-in colour, 0 is near-clean, 100 is heavy.

**Randomize.** Re-rolls the effect-to-slot assignment without touching the
buffers. The per-slot divisions are random on every trigger anyway, so a single
key reshuffles the whole character while your loops keep playing.

## Signal flow

```
                      audio IN
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
   dry (clean)                      record / overdub
        │                                   │
        │                             slot buffers
        │                                   │
        │                                 play
        │                                   │
        │                              slot effect
        │                                   │
        │                          bandpass + balance
        │                                   │
        │                            attack / decay
        │                                   │
        │                                crunch
        └─────────────────┬─────────────────┘
                          │
                     master gain
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
     OUT L/R           ~sendA            ~sendB
```

The live input is monitored clean and summed with the sampled voices. Record and
overdub capture from the input — and, with resample up, the playing loops folded
back in. Play routes a slot through its fixed effect, then the per-play scatter,
then its attack/decay envelope, then the shared crunch on the way to the sum.
Output volume scales the whole mix.

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
requires a hold.

## Screen

The screen is a single panel, centred. Everything sits at low brightness until a
state lifts it to full.

- **Record shield**, top left. Lights to full while the shield is engaged.
- **Three bars**, top right — output, record, play, top to bottom. Each fills
  pixel by pixel with its value, one pixel per percent, ten cells of ten.
- **Status row**, the eight slots in order. **P** playing, **R** recording, the
  angle a filled slot sitting idle, **X** empty. P and R show at full brightness.
- **Effect row**, aligned under the status row — the effect currently assigned to
  each slot. It reshuffles on Randomize. This is the one place the assignment is
  revealed; read a column top to bottom to see a slot's state and its effect.

## Parameters

In PARAMS menu order; all are MIDI-mappable.

| Parameter | Default | Range |
|-----------|---------|-------|
| **output volume** | 50 % | 0–100 % |
| **record probability** | 0 % | 0–100 % |
| **play probability** | 0 % | 0–100 % |
| **division decision** | on play | on play / on randomize |
| **division skew** | full range | short / long / full range |
| **sample attack** | 0 % | 0–100 % |
| **sample decay** | 0 % | 0–100 % |
| **resample** | no | no / yes |
| **resample amount** | 0 % | 0–100 % |
| **crunch amount** | 25 % | 0–100 % |
| **t: clear** | — | trigger |
| **t: shield** | — | trigger |
| **t: randomize** | — | trigger |

Output volume, record probability and play probability mirror the three encoders
(E1/E2/E3). Record and play default to 0 % so squid starts silent and waits for
you. Sample attack/decay are a fraction of each voice's play length. Crunch
defaults to the original baked-in colour (0 % near-clean, 100 % heavy). The three
trigger entries mirror the K1/K2/K3 actions for MIDI mapping — send a CC ≥ 64 to
fire.

## Synchronization

squid is locked to the Norns clock (internal or MIDI) and does nothing without
one. Each slot's per-trigger division is converted to beats:

| Division | beats |
|---|---|
| `4/1` | 16 |
| `2/1` | 8 |
| `1/1` | 4 |
| `1/2` | 2 |
| `1/4` | 1 |
| `1/8` | 0.5 |
| `1/16` | 0.25 |
| `1/32` | 0.125 |

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
