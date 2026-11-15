-- Dope Wars rules. Pure logic: no UI, no storage.
--
-- Left out on purpose: seeded dice, the action log, challenge rules and the
-- 60/90/365/unlimited modes. A game here is the classic 30 days.

local G = {}

-- The badge may run Lua with 32-bit integers: amounts are capped and money
-- never goes through floats.
local MAX = 2000000000

G.DAYS = 30
G.HEALTH_MAX = 100
G.HEAL_PRICE = 500
G.ESCAPE_ODDS = 60
G.CAUGHT_ODDS = 5
local PROB_EVENT = 77      -- out of 1000
local PROB_COPFIGHT = 115

-- { price_min, price_max, cheap, expensive }
G.GOODS = {
  { 1000, 4400, true, false },   -- 1 Acid
  { 15000, 29000, false, true }, -- 2 Cocaine
  { 480, 1280, true, false },    -- 3 Hashish
  { 5500, 13000, false, true },  -- 4 Heroin
  { 11, 60, true, false },       -- 5 Ludes
  { 1500, 4400, false, false },  -- 6 MDA
  { 540, 1250, false, true },    -- 7 Opium
  { 1000, 2500, false, false },  -- 8 PCP
  { 220, 700, false, false },    -- 9 Peyote
  { 630, 1300, false, false },   -- 10 Shrooms
  { 90, 250, false, true },      -- 11 Speed
  { 315, 890, true, false },     -- 12 Weed
}
local NGOODS = #G.GOODS

-- { bargain price, space, damage, precision (out of 100) }. The shop charges
-- five times the bargain price.
G.GUNS = {
  { 3600, 1, 5, 50 },  -- Baretta
  { 6500, 1, 9, 50 },  -- .38 Special
  { 2900, 1, 4, 60 },  -- Ruger
  { 5100, 1, 7, 65 },  -- Saturday Night Special
}

-- { health, attack, reward }
G.COPS = {
  { 50, 8, 1000 },    -- Officer Hardass
  { 75, 10, 3000 },   -- Officer Bob
  { 100, 14, 10000 }, -- Agent Smith
}

-- Six Tube stations:
-- 1 Kensington (Olympia), loan shark and starting point; 2 King's Cross, guns;
-- 3 Waterloo, hospital; 4 Victoria, bank; 5 Tottenham Court Road, nothing;
-- 6 Liverpool Street, bank.
G.CITIES = 6
G.SHARK_CITY = 1
G.GUNS_CITY = 2
G.HOSPITAL_CITY = 3

local function add(a, b)
  if a > MAX - b then return MAX end
  return a + b
end

-- 0 .. n-1
local function rnd(n)
  return math.random(0, n - 1)
end

-- Market ----------------------------------------------------------------------

local function draw_price(id)
  local g = G.GOODS[id]
  return g[1] + rnd(g[2] - g[1] + 1)
end

-- s.market: list of { id =, price =, ev = } sorted by id.
-- ev: 0 none, 1 expensive (x4), 2 cheap (/4).
function G.reset_market(s)
  local used, count, market = {}, 0, {}
  local wanted = 9 + rnd(NGOODS - 9 + 2) - 1 -- 8 .. 12 goods on sale

  local events = 0
  if rnd(100) < 70 then events = 1 end
  if events == 1 and rnd(100) < 40 then events = 2 end
  if events == 2 and rnd(100) < 5 then events = 3 end

  while events > 0 do
    local id = 1 + rnd(NGOODS)
    if not used[id] then
      local g = G.GOODS[id]
      if g[4] and (not g[3] or rnd(100) < 50) then
        market[#market + 1] = { id = id, price = draw_price(id) * 4, ev = 1 }
        used[id] = true
        count = count + 1
        events = events - 1
      elseif g[3] then
        market[#market + 1] = { id = id, price = draw_price(id) // 4, ev = 2 }
        used[id] = true
        count = count + 1
        events = events - 1
      end
    end
  end

  while count < wanted do
    local id = 1 + rnd(NGOODS)
    if not used[id] then
      market[#market + 1] = { id = id, price = draw_price(id), ev = 0 }
      used[id] = true
      count = count + 1
    end
  end

  table.sort(market, function(a, b) return a.id < b.id end)
  s.market = market
end

function G.price(s, id)
  for i = 1, #s.market do
    if s.market[i].id == id then return s.market[i].price end
  end
  return nil
end

-- New game ----------------------------------------------------------------------

function G.new()
  local s = {
    cash = 2000,
    debt = 5500,
    bank = 0,
    health = G.HEALTH_MAX,
    carry = 0,
    carry_max = 100,
    days_left = G.DAYS,
    city = 1,
    qty = {},   -- units carried, by good id
    paid = {},  -- average purchase price, by good id
    guns = {},  -- list of { k = kind, b = bought as a bargain }
    cops = {},  -- remaining health of each cop
    remaining = #G.COPS,
    fight = 0,  -- 0, or the index of the cop being fought
    dead = false,
  }
  for i = 1, NGOODS do
    s.qty[i] = 0
    s.paid[i] = 0
  end
  for i = 1, #G.COPS do s.cops[i] = G.COPS[i][1] end
  G.reset_market(s)
  return s
end

function G.day(s)
  return G.DAYS - s.days_left
end

function G.carry_left(s)
  return s.carry_max - s.carry
end

-- Goods -----------------------------------------------------------------------------

local function add_packet(s, id, n, price)
  if n < 1 then return end
  local q = s.qty[id]
  if q > 0 then
    s.paid[id] = (s.paid[id] * q + price * n) // (q + n)
  else
    s.paid[id] = price
  end
  s.qty[id] = q + n
  s.carry = s.carry + n
end

local function remove_packet(s, id, n)
  if n < 1 or n > s.qty[id] then return false end
  s.qty[id] = s.qty[id] - n
  if s.qty[id] == 0 then s.paid[id] = 0 end
  s.carry = s.carry - n
  return true
end

function G.max_buy(s, id)
  local price = G.price(s, id)
  if not price then return 0 end
  local n = s.cash // price
  local room = G.carry_left(s)
  if n > room then n = room end
  if n < 0 then n = 0 end
  return n
end

function G.buy(s, id, n)
  if n < 1 or n > G.max_buy(s, id) then return false end
  local price = G.price(s, id)
  s.cash = s.cash - price * n
  add_packet(s, id, n, price)
  return true
end

function G.sell(s, id, n)
  local price = G.price(s, id)
  if not price then return false end
  if not remove_packet(s, id, n) then return false end
  s.cash = add(s.cash, price * n)
  return true
end

-- Sells when the good is on the market, throws it away otherwise.
function G.drop(s, id, n)
  if G.price(s, id) then return G.sell(s, id, n) end
  return remove_packet(s, id, n)
end

-- Loan shark, bank, hospital ------------------------------------------------------------

function G.has_bank(s)
  return s.city == 4 or s.city == 6
end

function G.max_pay(s)
  if s.cash < s.debt then return s.cash end
  return s.debt
end

function G.pay_debt(s, n)
  if n < 1 or n > G.max_pay(s) then return false end
  s.cash = s.cash - n
  s.debt = s.debt - n
  return true
end

function G.deposit(s, n)
  if n < 1 or n > s.cash then return false end
  s.cash = s.cash - n
  s.bank = add(s.bank, n)
  return true
end

function G.withdraw(s, n)
  if n < 1 or n > s.bank then return false end
  s.bank = s.bank - n
  s.cash = add(s.cash, n)
  return true
end

-- after_kill: right after shooting a cop dead, healing is offered anywhere.
function G.can_heal(s, after_kill)
  local here = after_kill or (s.fight == 0 and s.city == G.HOSPITAL_CITY)
  return here and s.cash >= G.HEAL_PRICE and s.health < G.HEALTH_MAX
end

function G.heal(s)
  if s.cash < G.HEAL_PRICE then return false end
  s.cash = s.cash - G.HEAL_PRICE
  s.health = G.HEALTH_MAX
  return true
end

function G.buy_coat(s, pockets, price)
  if s.cash < price then return false end
  s.carry_max = s.carry_max + pockets
  s.cash = s.cash - price
  return true
end

-- Guns ----------------------------------------------------------------------------------

function G.gun_price(kind, bargain)
  if bargain then return G.GUNS[kind][1] end
  return G.GUNS[kind][1] * 5
end

local function owns_shop_gun(s, kind)
  for i = 1, #s.guns do
    if s.guns[i].k == kind and not s.guns[i].b then return true end
  end
  return false
end

-- Returns true, or false and a reason: "cash", "space" or "owned".
-- A bargain gun is one of a kind: it never counts as owned and needs no room.
function G.can_buy_gun(s, kind, bargain)
  if s.cash < G.gun_price(kind, bargain) then return false, "cash" end
  if not bargain then
    if G.carry_left(s) < G.GUNS[kind][2] then return false, "space" end
    if owns_shop_gun(s, kind) then return false, "owned" end
  end
  return true
end

function G.buy_gun(s, kind, bargain)
  local ok, why = G.can_buy_gun(s, kind, bargain)
  if not ok then return false, why end
  s.cash = s.cash - G.gun_price(kind, bargain)
  s.carry = s.carry + G.GUNS[kind][2]
  s.guns[#s.guns + 1] = { k = kind, b = bargain and true or false }
  return true
end

-- The gun the player fires with: the one that hits hardest. nil without one.
function G.best_gun(s)
  local best
  for i = 1, #s.guns do
    local k = s.guns[i].k
    if not best or G.GUNS[k][3] > G.GUNS[best][3] then best = k end
  end
  return best
end

-- Travel ----------------------------------------------------------------------------------

-- A branch that needs room in the bag falls through to
-- the next ones when the bag is full. Returns nil when nothing can happen.
local function random_event(s)
  local dice = rnd(1000)
  local left = G.carry_left(s)
  if dice < 56 and left > 0 then
    local n = rnd(6) + 3
    if n > left then n = left end
    return { type = "friend", n = n, id = 1 + rnd(NGOODS) }
  elseif dice < 167 and left > 0 then
    local n = rnd(4) + 1
    if n > left then n = left end
    return { type = "corpse", n = n, id = 1 + rnd(NGOODS) }
  elseif dice < 334 then
    local lost = 0
    if s.cash > 0 then lost = rnd(s.cash) end
    return { type = "mugged", cash = lost }
  elseif dice < 778 then
    return { type = "coat", price = rnd(150) + 200, pockets = rnd(10) + 10 }
  elseif dice < 834 then
    local carried = {}
    for id = 1, NGOODS do
      if s.qty[id] > 0 then carried[#carried + 1] = id end
    end
    if #carried == 0 then return nil end
    local id = carried[1 + rnd(#carried)]
    local n = rnd(4) + 1
    if n > s.qty[id] then n = s.qty[id] end
    return { type = "dogs", n = n, id = id }
  end
  return { type = "gun", kind = 1 + rnd(#G.GUNS) }
end

local function start_fight(s)
  for i = 1, #G.COPS do
    if s.cops[i] > 0 and s.remaining >= #G.COPS - (i - 1) then
      s.fight = i
      return true
    end
  end
  return false
end

-- One day passes. Returns the random event (already applied, except the coat
-- and gun offers which wait for an answer), or nil. A fight may have started:
-- check s.fight.
function G.move(s, city)
  if city == s.city or city < 1 or city > G.CITIES then return nil end
  if s.days_left <= 0 or s.fight ~= 0 then return nil end
  s.city = city
  s.debt = add(s.debt, s.debt // 10) -- x1.10
  s.bank = add(s.bank, s.bank // 20) -- x1.05
  s.days_left = s.days_left - 1
  G.reset_market(s)

  local dice = rnd(1000)
  if dice < PROB_EVENT then
    local ev = random_event(s)
    if ev then
      if ev.type == "friend" or ev.type == "corpse" then
        add_packet(s, ev.id, ev.n, 0)
      elseif ev.type == "mugged" then
        s.cash = s.cash - ev.cash
      elseif ev.type == "dogs" then
        remove_packet(s, ev.id, ev.n)
      end
    end
    return ev
  elseif dice < PROB_EVENT + PROB_COPFIGHT then
    start_fight(s)
  end
  return nil
end

-- Fights ------------------------------------------------------------------------------------

-- The cops seize all the dope and half the cash; guns stay.
local function seize(s)
  for id = 1, NGOODS do
    s.qty[id] = 0
    s.paid[id] = 0
  end
  s.carry = 0
  for i = 1, #s.guns do
    s.carry = s.carry + G.GUNS[s.guns[i].k][2]
  end
  s.cash = s.cash // 2
end

local function damage(base)
  return math.floor(base * (0.5 + math.random()))
end

-- The cop's reply. r.taken: damage, or 0 for a miss.
local function cop_turn(s, r)
  r.taken = 0
  if rnd(100) < 50 then
    r.taken = damage(G.COPS[s.fight][2])
    s.health = s.health - r.taken
    if s.health <= 0 then
      s.health = 0
      s.dead = true
      r.status = "dead"
      seize(s)
      s.fight = 0
    end
  end
end

-- Returns { status =, taken = }.
-- status: "escaped", "caught", "remain" (the chase goes on) or "dead".
function G.run(s)
  local r = { status = "remain" }
  if s.fight == 0 then return r end
  local dice = rnd(100)
  if dice < G.ESCAPE_ODDS then
    r.status = "escaped"
    s.fight = 0
  elseif dice < G.ESCAPE_ODDS + G.CAUGHT_ODDS then
    r.status = "caught"
    seize(s)
    s.fight = 0
  else
    cop_turn(s, r)
  end
  return r
end

-- Returns { status =, given =, taken =, cop = }.
-- status: "hit", "miss", "kill" or "dead". given: damage dealt, nil on a miss.
function G.strike(s)
  local r = { status = "miss", cop = s.fight }
  local gun = G.best_gun(s)
  if s.fight == 0 or not gun then return r end
  if rnd(100) < G.GUNS[gun][4] then
    r.given = damage(G.GUNS[gun][3])
    r.status = "hit"
    local left = s.cops[s.fight] - r.given
    if left <= 0 then
      s.cops[s.fight] = 0
      s.cash = add(s.cash, G.COPS[s.fight][3])
      s.remaining = s.remaining - 1
      s.fight = 0
      r.status = "kill"
      return r
    end
    s.cops[s.fight] = left
  end
  cop_turn(s, r)
  return r
end

-- Score ----------------------------------------------------------------------------------------

-- Cash plus bank minus twice the debt, floored at zero.
function G.score(s)
  if s.debt >= MAX // 2 then return 0 end
  local net = add(s.cash, s.bank) - 2 * s.debt
  if net < 0 then return 0 end
  return net
end

return G
