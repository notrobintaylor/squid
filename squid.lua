-- squid
--
-- 8 probabilistic samplers
-- 8 seconds each, retro crunch
-- 8 effects, spectral mixer

local sprite = include("lib/sprite_squid")
local OX, OY = sprite.origin.x, sprite.origin.y

local NUM_SLOTS = 8
local NUM_BANDS = 3
local NUM_PANS = 5

-- full division spectrum (beats), slowest -> fastest; range bounded by the
-- 8 s buffer over 20-300 BPM (see session notes). skew biases selection
-- toward one end but never excludes the other
local DIV_SPECTRUM = { 32, 16, 8, 4, 2, 1, 0.5, 0.25, 0.125, 0.0625 }
local DIV_TILT = 0.5   -- +/- weighting at the ends; short favors fast, long slow

local STATE_GLYPH = { play = "p", rec = "r", idle = "angle", empty = "x" }
local STATE_LEVEL = { play = 15, rec = 15, idle = 5, empty = 5 }

local engine_ready = false
local record_shield = false
local k1_clock = nil
local redraw_clock = nil

local in_amp = { l = 0, r = 0 }      -- live Norns input amplitude (L/R)
local meter_disp = { l = 0, r = 0 }  -- meter ballistics: fast attack, slow release
local in_polls = {}

local slot_fx = {}
local slot_filled = {}
local slot_div = {}
local slot_band = {}
local slot_pan = {}
local slot_level = {}
local slot_muted = {}
local slot_shield = {}
local slot_len = {}
local slot_state = {}
local slot_until = {}
local slot_clocks = {}

-- =========================================================================
-- slot state
-- =========================================================================

local function revert_target(slot)
  return slot_filled[slot] and "idle" or "empty"
end

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

-- per-skew weight over DIV_SPECTRUM: short tilts toward fast, long toward
-- slow, full range stays flat. linear, +/-DIV_TILT at the two ends
local function div_weights()
  local skew = params:get("squid_skew")
  local s = (skew == 1) and 1 or (skew == 2) and -1 or 0
  local n = #DIV_SPECTRUM
  local w = {}
  for i = 1, n do
    local p = (i - 1) / (n - 1)            -- 0 = slowest, 1 = fastest
    w[i] = 1 + s * DIV_TILT * (2 * p - 1)
  end
  return w
end

-- weighted pick with replacement; used by the "on play" decision mode
local function pick_div()
  local w = div_weights()
  local total = 0
  for i = 1, #w do total = total + w[i] end
  local r = math.random() * total
  local acc = 0
  for i = 1, #DIV_SPECTRUM do
    acc = acc + w[i]
    if r <= acc then return DIV_SPECTRUM[i] end
  end
  return DIV_SPECTRUM[#DIV_SPECTRUM]
end

-- assign each slot a unique division: weighted draw without replacement, so
-- the skew biases which values appear (and which drop out) without excluding
-- an end; used by the "on randomize" decision mode
local function reroll_slot_divs()
  local w = div_weights()
  local vals, wts = {}, {}
  for i = 1, #DIV_SPECTRUM do vals[i] = DIV_SPECTRUM[i]; wts[i] = w[i] end
  for k = 1, NUM_SLOTS do
    local total = 0
    for i = 1, #wts do total = total + wts[i] end
    local r = math.random() * total
    local acc, idx = 0, #vals
    for i = 1, #vals do
      acc = acc + wts[i]
      if r <= acc then idx = i; break end
    end
    slot_div[k] = vals[idx]
    table.remove(vals, idx)
    table.remove(wts, idx)
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

-- effective per-slot gain: muted -> 0, else the fader level
local function push_slot_amp(slot)
  if engine_ready then
    engine.slot_amp(slot - 1, slot_muted[slot] and 0 or slot_level[slot])
  end
end

-- assign each slot a unique matrix cell (band, pan), 0-based; never duplicated
local function reroll_matrix_cells()
  local cells = {}
  for b = 0, NUM_BANDS - 1 do
    for p = 0, NUM_PANS - 1 do
      cells[#cells + 1] = { b, p }
    end
  end
  for i = #cells, 2, -1 do
    local j = math.random(i)
    cells[i], cells[j] = cells[j], cells[i]
  end
  for i = 1, NUM_SLOTS do
    slot_band[i] = cells[i][1]
    slot_pan[i] = cells[i][2]
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
  reroll_matrix_cells()
  if engine_ready then push_assignments() end
end

-- =========================================================================
-- triggering
-- =========================================================================

-- shared play/record actions (used by the probability loop and manual triggers)
local function do_play(slot)
  engine.play(slot - 1, slot_band[slot], slot_pan[slot])
  if slot_filled[slot] then set_slot_state(slot, "play", slot_len[slot]) end
end

local function do_record(slot, beats)
  if record_shield or slot_shield[slot] then return end
  local dur = math.min(beats * clock.get_beat_sec(), 8)
  if slot_filled[slot] then
    engine.dub(slot - 1, dur)
  else
    engine.rec(slot - 1, dur)
    slot_filled[slot] = true
  end
  slot_len[slot] = dur
  set_slot_state(slot, "rec", dur)
end

-- manual trigger: fire now, or sync to the slot's division when quantized
local function manual_fire(slot, action)
  if params:get("squid_manual_quantize") == 2 then
    clock.run(function()
      clock.sync(slot_div[slot])
      action(slot)
    end)
  else
    action(slot)
  end
end

local function fire_trigger(slot, beats)
  if math.random(100) <= params:get("squid_play_prob") then
    do_play(slot)
    return
  end
  if math.random(100) <= params:get("squid_rec_prob") then
    do_record(slot, beats)
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

  params:add_group("squid_global", "global", 16)

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
  params:add_option("squid_manual_quantize", "manual quantize", {"free", "quantized"}, 1)
  params:add_binary("squid_trig_clear", "t: clear", "trigger", 0)
  params:set_action("squid_trig_clear", function(v) if v == 1 then clear_all() end end)
  params:add_binary("squid_trig_shield", "t: shield", "trigger", 0)
  params:set_action("squid_trig_shield", function(v) if v == 1 then record_shield = not record_shield end end)
  params:add_binary("squid_trig_randomize", "t: randomize", "trigger", 0)
  params:set_action("squid_trig_randomize", function(v) if v == 1 then randomize() end end)
  params:add_binary("squid_trig_gmute", "t: global mute", "trigger", 0)
  params:set_action("squid_trig_gmute", function(z)
    if z == 1 then for i = 1, NUM_SLOTS do slot_muted[i] = true; push_slot_amp(i) end end
  end)
  params:add_binary("squid_trig_gmute_flip", "t: global mute flip", "trigger", 0)
  params:set_action("squid_trig_gmute_flip", function(z)
    if z == 1 then for i = 1, NUM_SLOTS do slot_muted[i] = not slot_muted[i]; push_slot_amp(i) end end
  end)

  for i = 1, NUM_SLOTS do
    params:add_group("squid_slot_" .. i, "slot " .. i, 5)
    params:add_control("squid_level_" .. i, "level s" .. i,
      controlspec.new(0, 1, "lin", 0, 1, ""), pct01)
    params:set_action("squid_level_" .. i, function(v) slot_level[i] = v; push_slot_amp(i) end)
    params:add_binary("squid_trig_mute_" .. i, "t: mute s" .. i, "trigger", 0)
    params:set_action("squid_trig_mute_" .. i, function(z)
      if z == 1 then slot_muted[i] = not slot_muted[i]; push_slot_amp(i) end
    end)
    params:add_binary("squid_trig_play_" .. i, "t: play s" .. i, "trigger", 0)
    params:set_action("squid_trig_play_" .. i, function(z)
      if z == 1 then manual_fire(i, do_play) end
    end)
    params:add_binary("squid_trig_rec_" .. i, "t: rec s" .. i, "trigger", 0)
    params:set_action("squid_trig_rec_" .. i, function(z)
      if z == 1 then manual_fire(i, function(s) do_record(s, slot_div[s]) end) end
    end)
    params:add_binary("squid_trig_shield_" .. i, "t: record shield s" .. i, "trigger", 0)
    params:set_action("squid_trig_shield_" .. i, function(z)
      if z == 1 then slot_shield[i] = not slot_shield[i] end
    end)
  end
end

-- =========================================================================
-- init / cleanup
-- =========================================================================

local function start_input_polls()
  local pl = poll.set("amp_in_l", function(v) in_amp.l = v end)
  pl.time = 1 / 15
  pl:start()
  local pr = poll.set("amp_in_r", function(v) in_amp.r = v end)
  pr.time = 1 / 15
  pr:start()
  in_polls = { pl, pr }
end

local function stop_input_polls()
  for _, p in ipairs(in_polls) do p:stop() end
  in_polls = {}
end

function init()
  math.randomseed(os.time())
  for i = 1, NUM_SLOTS do
    slot_filled[i] = false
    slot_len[i] = 0
    slot_state[i] = "empty"
    slot_until[i] = 0
    slot_level[i] = 1.0
    slot_muted[i] = false
    slot_shield[i] = false
  end
  add_params()
  randomize()
  engine.load("Squid", function()
    engine_ready = true
    params:bang()
    push_assignments()
    start_loops()
    start_input_polls()
    redraw_clock = clock.run(function()
      while true do
        clock.sleep(1 / 10)
        redraw()
      end
    end)
    redraw()
  end)
end

function cleanup()
  stop_loops()
  stop_input_polls()
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

local function fill_rects(rs)
  for _, r in ipairs(rs) do screen.rect(OX + r[1], OY + r[2], r[3], r[4]) end
end

-- input meter column: body @5 up to the peak dash, peak dash @15, above dark.
-- segs ordered bottom -> top; amplitude mapped on a dB scale (input is quiet,
-- linear would barely move). METER_DB_FLOOR..0 dB -> 0..#segs
local METER_DB_FLOOR = -50
-- meter ballistics as time constants in beats -> they track the BPM
local METER_ATTACK_BEATS = 0.02   -- rise (small = snappy peaks)
local METER_RELEASE_BEATS = 1.0   -- fall (larger = more sluggish)
local REDRAW_DT = 1 / 10          -- redraw period; matches the redraw clock

local function draw_meter(segs, amp)
  local n = 0
  if amp > 0 then
    local db = 20 * math.log(amp) / math.log(10)
    local f = (db - METER_DB_FLOOR) / -METER_DB_FLOOR
    if f > 1 then f = 1 end
    if f > 0 then n = math.floor(f * #segs + 0.5) end
  end
  if n < 1 then return end
  if n > 1 then
    screen.level(5)
    for i = 1, n - 1 do draw_pixels(segs[i], 0, 0) end
    screen.fill()
  end
  screen.level(15)
  draw_pixels(segs[n], 0, 0)
  screen.fill()
end

-- one-pole follower; attack/release time constants given in beats -> BPM-coupled
local function meter_follow(disp, amp)
  local beats = (amp > disp) and METER_ATTACK_BEATS or METER_RELEASE_BEATS
  local a = 1 - math.exp(-REDRAW_DT / (beats * clock.get_beat_sec()))
  return disp + (amp - disp) * a
end

local function draw_fader(f, level, muted)
  -- frame: bright = active, dim = muted
  screen.level(muted and 5 or 15)
  for x = f.x0, f.x1 do
    screen.rect(OX + x, OY + f.y0, 1, 1)
    screen.rect(OX + x, OY + f.y1, 1, 1)
  end
  for y = f.y0, f.y1 do
    screen.rect(OX + f.x0, OY + y, 1, 1)
    screen.rect(OX + f.x1, OY + y, 1, 1)
  end
  screen.fill()
  -- handle: always bright, y follows the level
  screen.level(15)
  local ty = f.y1 - 2 - math.floor(level * 10 + 0.5)
  for x = f.hx0, f.hx1 do
    screen.rect(OX + x, OY + ty, 1, 1)
    screen.rect(OX + x, OY + ty + 1, 1, 1)
  end
  screen.fill()
end

-- R1 status-cell frame: drawn @15 when the slot can record, left dim (chrome @5)
-- when record-shielded. x spans the slot's dividers, y is the R1 cell box
local R1_Y0, R1_Y1 = 19, 26

local function draw_status_frame(s)
  local x0 = sprite.slot_cells[s].x - 1
  local x1 = sprite.slot_cells[s].x + 8
  for x = x0, x1 do
    screen.rect(OX + x, OY + R1_Y0, 1, 1)
    screen.rect(OX + x, OY + R1_Y1, 1, 1)
  end
  for y = R1_Y0, R1_Y1 do
    screen.rect(OX + x0, OY + y, 1, 1)
    screen.rect(OX + x1, OY + y, 1, 1)
  end
end

function redraw()
  update_slot_states()
  screen.clear()

  screen.level(5)
  fill_rects(sprite.chrome)
  screen.fill()

  screen.level(record_shield and 15 or 5)
  draw_pixels(sprite.shield, 0, 0)
  screen.fill()

  meter_disp.l = meter_follow(meter_disp.l, in_amp.l)
  meter_disp.r = meter_follow(meter_disp.r, in_amp.r)
  draw_meter(sprite.meter_L, meter_disp.l)
  draw_meter(sprite.meter_R, meter_disp.r)

  screen.level(15)
  draw_pixels(sprite.slot_numbers, 0, 0)
  screen.fill()

  screen.level(15)
  for pi = 1, 3 do
    local bar = sprite.param_bars[pi]
    local n = bar_value(pi)
    if n > #bar then n = #bar end
    for i = 1, n do
      local p = bar[i]
      screen.rect(OX + p[1], OY + p[2], 1, 1)
    end
  end
  screen.fill()

  for s = 1, NUM_SLOTS do
    draw_fader(sprite.fader_cells[s], slot_level[s], slot_muted[s])
  end

  screen.level(15)
  for s = 1, NUM_SLOTS do
    if not slot_shield[s] then draw_status_frame(s) end
  end
  screen.fill()

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

  screen.level(15)
  for s = 1, NUM_SLOTS do
    local g = sprite.effect_glyphs[slot_fx[s]]
    if g then
      local c = sprite.effect_cells[s]
      draw_pixels(g, c.x, c.y)
    end
  end
  screen.fill()

  -- matrix: light each playing slot's cell (never dim, only @15 while playing).
  -- band 0 (low) -> bottom row, pan 0 (hard left) -> left column
  screen.level(15)
  for s = 1, NUM_SLOTS do
    if slot_state[s] == "play" and not slot_muted[s] then
      local cell = sprite.matrix_cells[3 - slot_band[s]][slot_pan[s] + 1]
      draw_pixels(cell, 0, 0)
    end
  end
  screen.fill()

  screen.update()
end
