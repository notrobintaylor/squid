-- squid
--
-- 8 probabilistic samplers
-- 8 seconds each, retro crunch
-- 8 effects, spectral mixer

local sprite = include("lib/sprite_squid")
local OX, OY = sprite.origin.x, sprite.origin.y

local NUM_SLOTS = 8

-- division pools (beats), indexed by squid_skew (1 = short, 2 = long, 3 = full).
-- Split at 1/1 (1/1 belongs to long):
--   long  = 4/1, 2/1, 1/1
--   short = 1/2, 1/4, 1/8, 1/16, 1/32
--   full  = all eight (1/1 = one bar)
local SKEW_DIVS = {
  {2, 1, 0.5, 0.25, 0.125},
  {16, 8, 4},
  {16, 8, 4, 2, 1, 0.5, 0.25, 0.125},
}

-- slot status -> glyph name + brightness
local STATE_GLYPH = { play = "p", rec = "r", idle = "angle", empty = "x" }
local STATE_LEVEL = { play = 15, rec = 15, idle = 5, empty = 5 }

local engine_ready = false
local record_shield = false
local k1_clock = nil
local redraw_clock = nil

-- slot_fx[i]: effect id (1-8) assigned to slot i; each id used once
local slot_fx = {}
-- slot_filled[i]: false = empty (record fresh), true = has content (overdub)
local slot_filled = {}
-- slot_div[i]: per-slot fixed division (beats) when squid_div_decision = "on randomize"
local slot_div = {}
-- slot_len[i]: last recorded length in seconds (used to time the play glyph)
local slot_len = {}
-- slot_state[i]: empty / idle / play / rec
local slot_state = {}
-- slot_until[i]: util.time() at which a play/rec glyph reverts to idle/empty
local slot_until = {}
-- slot_clocks[i]: clock id of slot i's trigger loop
local slot_clocks = {}

-- =========================================================================
-- slot state
-- =========================================================================

local function revert_target(slot)
  return slot_filled[slot] and "idle" or "empty"
end

-- A play/rec glyph holds until slot_until, then reverts. We use a timestamp
-- checked each redraw frame, not a per-trigger clock: spawning and cancelling a
-- clock on every trigger raced the scheduler into resuming a cancelled coroutine
-- (clock.lua "thread expected").
local function set_slot_state(slot, st, dur)
  slot_state[slot] = st
  slot_until[slot] = util.time() + dur
end

local function update_slot_states()
  local now = util.time()
  for i = 1, NUM_SLOTS do
    local st = slot_state[i]
    if (st == "play" or st == "rec") and now >= slot_until[i] then
      slot_state[i] = revert_target(i)
    end
  end
end

-- =========================================================================
-- divisions
-- =========================================================================

local function pick_div()
  local divs = SKEW_DIVS[params:get("squid_skew")]
  return divs[math.random(#divs)]
end

local function reroll_slot_divs()
  for i = 1, NUM_SLOTS do
    slot_div[i] = pick_div()
  end
end

-- =========================================================================
-- effect assignment
-- =========================================================================

local function push_assignments()
  for i = 1, NUM_SLOTS do
    engine.set_effect(i - 1, slot_fx[i])
  end
end

local function randomize()
  local perm = {1, 2, 3, 4, 5, 6, 7, 8}
  for i = #perm, 2, -1 do
    local j = math.random(i)
    perm[i], perm[j] = perm[j], perm[i]
  end
  slot_fx = perm
  reroll_slot_divs()
  if engine_ready then push_assignments() end
end

-- =========================================================================
-- triggering
-- =========================================================================

local function fire_trigger(slot, beats)
  local dur = math.min(beats * clock.get_beat_sec(), 8)
  if math.random(100) <= params:get("squid_play_prob") then
    engine.play(slot - 1)
    if slot_filled[slot] then set_slot_state(slot, "play", slot_len[slot]) end
    return
  end
  if record_shield then return end
  if math.random(100) <= params:get("squid_rec_prob") then
    if slot_filled[slot] then
      engine.dub(slot - 1, dur)
    else
      engine.rec(slot - 1, dur)
      slot_filled[slot] = true
    end
    slot_len[slot] = dur
    set_slot_state(slot, "rec", dur)
  end
end

local function slot_loop(slot)
  while true do
    local beats
    if params:get("squid_div_decision") == 2 then
      beats = slot_div[slot]
    else
      beats = pick_div()
    end
    clock.sync(beats)
    fire_trigger(slot, beats)
  end
end

local function stop_loops()
  for i = 1, #slot_clocks do
    if slot_clocks[i] then clock.cancel(slot_clocks[i]) end
  end
  slot_clocks = {}
end

local function start_loops()
  stop_loops()
  for i = 1, NUM_SLOTS do
    slot_clocks[i] = clock.run(slot_loop, i)
  end
end

local function clear_all()
  engine.clear_all()
  for i = 1, NUM_SLOTS do
    slot_filled[i] = false
    slot_len[i] = 0
    slot_state[i] = "empty"
    slot_until[i] = 0
  end
end

-- =========================================================================
-- params
-- =========================================================================

local function bar_value(pi)
  if pi == 1 then
    return util.clamp(math.floor(params:get("squid_output") * 100 + 0.5), 0, 100)
  elseif pi == 2 then
    return params:get("squid_rec_prob")
  else
    return params:get("squid_play_prob")
  end
end

local function push_resample()
  local on = params:get("squid_resample") == 2
  engine.resample(on and (params:get("squid_resample_amt") / 100) or 0)
end

local function pct(p) return p:get() .. "%" end
local function pct01(p) return math.floor(p:get() * 100 + 0.5) .. "%" end

local function add_params()
  params:add_separator("squid_sep", "squid")

  params:add_control("squid_output", "output volume",
    controlspec.new(0, 1, "lin", 0, 0.5, ""), pct01)
  params:set_action("squid_output", function(v) engine.output(v) end)

  params:add_number("squid_rec_prob", "record probability", 0, 100, 0, pct)
  params:add_number("squid_play_prob", "play probability", 0, 100, 0, pct)

  params:add_option("squid_div_decision", "division decision", {"on play", "on randomize"}, 1)
  params:add_option("squid_skew", "division skew", {"short", "long", "full range"}, 3)
  params:set_action("squid_skew", reroll_slot_divs)

  params:add_number("squid_attack", "sample attack", 0, 100, 0, pct)
  params:set_action("squid_attack", function(v) engine.attack(v / 100) end)
  params:add_number("squid_decay", "sample decay", 0, 100, 0, pct)
  params:set_action("squid_decay", function(v) engine.decay(v / 100) end)

  params:add_option("squid_resample", "resample", {"no", "yes"}, 1)
  params:set_action("squid_resample", push_resample)
  params:add_number("squid_resample_amt", "resample amount", 0, 100, 0, pct)
  params:set_action("squid_resample_amt", push_resample)

  params:add_number("squid_crunch", "crunch amount", 0, 100, 25, pct)
  params:set_action("squid_crunch", function(v) engine.crunch(v) end)

  params:add_trigger("squid_trig_clear", "t: clear")
  params:set_action("squid_trig_clear", function() clear_all() end)
  params:add_trigger("squid_trig_shield", "t: shield")
  params:set_action("squid_trig_shield", function() record_shield = not record_shield end)
  params:add_trigger("squid_trig_randomize", "t: randomize")
  params:set_action("squid_trig_randomize", function() randomize() end)
end

-- =========================================================================
-- init / cleanup
-- =========================================================================

function init()
  math.randomseed(os.time())
  for i = 1, NUM_SLOTS do
    slot_filled[i] = false
    slot_len[i] = 0
    slot_state[i] = "empty"
    slot_until[i] = 0
  end
  add_params()
  randomize()
  engine.load("Squid", function()
    engine_ready = true
    params:bang()
    push_assignments()
    start_loops()
    redraw_clock = clock.run(function()
      while true do
        clock.sleep(1 / 15)
        redraw()
      end
    end)
    redraw()
  end)
end

function cleanup()
  stop_loops()
  if redraw_clock then clock.cancel(redraw_clock) end
end

-- =========================================================================
-- input
-- =========================================================================

function enc(n, d)
  if n == 1 then
    params:delta("squid_output", d)
  elseif n == 2 then
    params:delta("squid_rec_prob", d)
  elseif n == 3 then
    params:delta("squid_play_prob", d)
  end
  redraw()
end

function key(n, z)
  -- K1: norns reserves a short tap for its menu, so clear fires only on a 2 s hold
  if n == 1 then
    if z == 1 then
      k1_clock = clock.run(function()
        clock.sleep(2)
        clear_all()
        k1_clock = nil
      end)
    elseif k1_clock then
      clock.cancel(k1_clock)
      k1_clock = nil
    end
    return
  end
  if z == 1 then
    if n == 2 then
      record_shield = not record_shield
    elseif n == 3 then
      randomize()
    end
  end
end

-- =========================================================================
-- screen
-- =========================================================================

local function draw_pixels(pts, cx, cy)
  for _, p in ipairs(pts) do screen.rect(OX + cx + p[1], OY + cy + p[2], 1, 1) end
end

function redraw()
  update_slot_states()
  screen.clear()

  -- static base
  screen.level(5)
  draw_pixels(sprite.static_base, 0, 0)
  screen.fill()

  -- record shield
  screen.level(record_shield and 15 or 5)
  draw_pixels(sprite.shield, 0, 0)
  screen.fill()

  -- param bars (output / rec / play), filled portion only
  screen.level(5)
  for pi = 1, 3 do
    local bar = sprite.param_bars[pi]
    for i = 1, bar_value(pi) do
      local p = bar[i]
      screen.rect(OX + p[1], OY + p[2], 1, 1)
    end
  end
  screen.fill()

  -- slot status glyphs, batched by brightness
  for _, lv in ipairs({15, 5}) do
    screen.level(lv)
    for s = 1, NUM_SLOTS do
      local st = slot_state[s]
      if STATE_LEVEL[st] == lv then
        local c = sprite.slot_cells[s]
        draw_pixels(sprite.glyphs[STATE_GLYPH[st]], c.x, c.y)
      end
    end
    screen.fill()
  end

  -- effect per slot, column-aligned under the status row (level 5)
  screen.level(5)
  for s = 1, NUM_SLOTS do
    local g = sprite.effect_glyphs[slot_fx[s]]
    if g then
      local c = sprite.effect_cells[s]
      draw_pixels(g, c.x, c.y)
    end
  end
  screen.fill()

  screen.update()
end
