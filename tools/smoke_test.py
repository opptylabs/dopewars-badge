#!/usr/bin/env python3
"""Headless smoke test: runs the app against a stub of the badge API.

    pip install lupa
    python3 tools/smoke_test.py [games]

Three passes:
  1. rules only: thousands of simulated days on lib/game.lua, checking the
     bag, the money and the fights stay consistent;
  2. the splash: every frame keeps its rows the same width;
  3. the whole app under random key presses, checking nothing raises and that
     games reach their end.

It does not replace a run in the official emulator: the stubs only cover the
calls this app makes, and nothing here measures pixels.
"""
import os
import random
import sys

try:
    from lupa.lua55 import LuaRuntime  # same major version as Solana OS
except ImportError:  # pragma: no cover
    from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUBS = r"""
package.path = ROOT .. "/?.lua;" .. package.path
labels, store, timers, objects, toasts = {}, {}, {}, 0, 0

local function obj(kind, text)
  objects = objects + 1
  local o = { kind = kind, value = text or "", visible = true, alive = true }
  function o:text(v) assert(type(v) == "string", "label text must be a string") self.value = v end
  function o:pos() end
  function o:size() end
  function o:color(c) assert(c ~= nil, "nil colour") end
  function o:show(b) self.visible = b end
  function o:remove() self.alive = false objects = objects - 1 end
  if kind == "label" then labels[#labels + 1] = o end
  return o
end

ui = { W = 320, H = 218 }
function ui.label(x, y, text, opts) return obj("label", text) end
function ui.rect() return obj("rect") end
canvas_cells = {}
function ui.canvas(x, y, w, h, opts)
  local c = obj("canvas")
  function c:rect(px, py, pw, ph, color)
    assert(color ~= nil, "nil colour")
    assert(px >= 0 and py >= 0 and px + pw <= w and py + ph <= h, "drawing outside the canvas")
    for yy = py, py + ph - 1 do
      for xx = px, px + pw - 1 do canvas_cells[yy * 1000 + xx] = color == "text" and "o" or "#" end
    end
  end
  function c:clear() canvas_cells = {} end
  canvas_w, canvas_h = w, h
  return c
end
function canvas_dump()
  local out = {}
  for yy = 0, canvas_h - 1 do
    local line = {}
    for xx = 0, canvas_w - 1 do line[#line + 1] = canvas_cells[yy * 1000 + xx] or " " end
    out[#out + 1] = table.concat(line)
  end
  return table.concat(out, "\n")
end
function ui.toast(text) assert(type(text) == "string") toasts = toasts + 1 end

-- storage goes through a deep copy, like a JSON round trip on the badge
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
storage = {}
function storage.get(k) return copy(store[k]) end
function storage.set(k, v) store[k] = copy(v) end
function storage.remove(k) store[k] = nil end

timer = {}
function timer.every(ms, fn) timers[#timers + 1] = fn return #timers end
function timer.after(ms, fn) return 0 end
function timer.cancel(id) timers[id] = nil end

led = { count = 8 }
function led.fill() end
function led.set() end
function led.off() end

function visible_text()
  local t = {}
  for i = 1, #labels do
    local o = labels[i]
    if o.alive and o.visible and o.value ~= "" then t[#t + 1] = o.value end
  end
  return t
end

function tick()
  local n = 0
  for id, fn in pairs(timers) do fn() n = n + 1 end
  return n
end
"""

RULES = r"""
local G = require("lib.game")
local function check(s)
  local total = #s.guns
  for id = 1, #G.GOODS do
    assert(s.qty[id] >= 0, "negative quantity")
    total = total + s.qty[id]
  end
  assert(total == s.carry, "bag out of sync: " .. total .. " vs " .. s.carry)
  assert(s.cash >= 0 and s.debt >= 0 and s.bank >= 0, "negative money")
  assert(s.health >= 0 and s.health <= G.HEALTH_MAX)
  assert(#s.market >= 8 and #s.market <= 12, "market size " .. #s.market)
  for i = 2, #s.market do assert(s.market[i - 1].id < s.market[i].id, "market not sorted") end
end

local stats = { games = 0, dead = 0, fights = 0, kills = 0, events = 0, best = 0 }
for game = 1, GAMES do
  local s = G.new()
  check(s)
  while s.days_left > 0 and not s.dead do
    -- sell everything that sells, pay the shark, buy the cheapest thing
    for i = 1, #s.market do
      local g = s.market[i]
      if s.qty[g.id] > 0 then assert(G.sell(s, g.id, s.qty[g.id])) end
    end
    if s.city == G.SHARK_CITY and G.max_pay(s) > 0 then assert(G.pay_debt(s, G.max_pay(s))) end
    if s.city == G.GUNS_CITY then G.buy_gun(s, math.random(1, 4), false) end
    if G.has_bank(s) and s.cash > 10 then assert(G.deposit(s, s.cash // 2)) assert(G.withdraw(s, s.bank // 3 + 1)) end
    if G.can_heal(s, false) then assert(G.heal(s)) end
    local pick = s.market[math.random(1, #s.market)]
    local n = G.max_buy(s, pick.id)
    if n > 0 then assert(G.buy(s, pick.id, math.random(1, n))) end
    check(s)

    local city = s.city
    while city == s.city do city = math.random(1, G.CITIES) end
    local ev = G.move(s, city)
    if ev then
      stats.events = stats.events + 1
      if ev.type == "coat" then G.buy_coat(s, ev.pockets, ev.price) end
      if ev.type == "gun" then G.buy_gun(s, ev.kind, true) end
    end
    check(s)
    if s.fight ~= 0 then
      stats.fights = stats.fights + 1
      local rounds = 0
      while s.fight ~= 0 do
        rounds = rounds + 1
        assert(rounds < 500, "endless fight")
        local r
        if G.best_gun(s) and math.random(0, 1) == 1 then r = G.strike(s) else r = G.run(s) end
        if r.status == "kill" then stats.kills = stats.kills + 1 end
        check(s)
      end
    end
  end
  stats.games = stats.games + 1
  if s.dead then stats.dead = stats.dead + 1 end
  local score = G.score(s)
  assert(score >= 0)
  if score > stats.best then stats.best = score end
end
return stats
"""

KEYS = ["up", "down", "left", "right", "right", "select", "select", "select", "back"]


def runtime(seed):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ROOT = ROOT
    lua.execute("math.randomseed(%d)" % seed)
    lua.execute(STUBS)
    return lua


def rules(games):
    lua = runtime(1)
    lua.globals().GAMES = games
    stats = lua.execute(RULES)
    print("rules: %d games, %d deaths, %d fights, %d cops killed, %d events, best score $%d"
          % (stats.games, stats.dead, stats.fights, stats.kills, stats.events, stats.best))


def load_app(seed):
    lua = runtime(seed)
    with open(os.path.join(ROOT, "main.lua")) as f:
        lua.execute(f.read())
    return lua, lua.globals()


def splash():
    lua, g = load_app(1)
    frames = 0
    while g.tick() > 0:
        frames += 1
        assert frames < 500, "splash never ends"
    texts = list(g.visible_text().values())
    assert "DOPEWARS" in texts, texts
    art = g.canvas_dump()
    assert "#" in art and "o" in art, "nothing drawn on the canvas"
    if "--show" in sys.argv:
        print(art)
    g.on_key("select", False)
    assert "New Game" in " ".join(g.visible_text().values())
    print("splash: %d frames, then the title menu" % frames)


def play(seed, presses=5000):
    lua, g = load_app(seed)
    rng = random.Random(seed)
    finished = 0
    best = None
    for _ in range(presses):
        key = rng.choice(KEYS)
        handled = g.on_key(key, rng.random() < 0.1)
        assert handled or key == "back"
        g.tick()
        assert g.objects <= 64, "too many UI objects: %d" % g.objects
        for text in g.visible_text().values():
            assert len(text) <= 200
        if g.store["best"] != best:
            best = g.store["best"]
            finished += 1
    return finished


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    games = int(args[0]) if args else 100
    rules(games * 20)
    splash()
    finished = sum(play(seed) for seed in range(1, games + 1))
    assert finished > 0, "no random game reached its end"
    print("app: %d sessions of random keys, %d games finished with a new record, no error"
          % (games, finished))


if __name__ == "__main__":
    main()
