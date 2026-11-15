-- Dopewars for the Solana Breakpoint 2026 badge (Solana OS, Lua sandbox).
-- Screens, input and game flow. Rules are in lib/game.lua, strings in
-- lib/texts.lua. Layout: a status header, the
-- market as the main screen, and sheets for everything else.

local G = require("lib.game")
local T = require("lib.texts")

local W = ui.W
local WRAP = 34        -- characters per line in a sheet (size 14)
local ROW_H = 18
local LIST_Y = 52
local HUB_ROWS = 7     -- market rows visible at once
local SHEET_ROWS = 6

local RED = 0xB10000

local s                -- game state (see G.new), nil on the title screen
local mode = "splash"  -- "splash", "hub" or "sheet"
local sheet            -- current sheet: { draw = fn, key = fn }
local hub, view        -- UI objects, built once the splash is gone
local entries = {}     -- hub list: { id =, price =, ev = }, price nil if not sold here
local cursor, top = 1, 1
local blink            -- LED timer id during a fight

-- Formatting ----------------------------------------------------------------------

local function money(n)
  local str, out = tostring(n), ""
  while #str > 3 do
    out = "," .. str:sub(-3) .. out
    str = str:sub(1, -4)
  end
  return "$" .. str .. out
end

-- Three figures for a tight spot: $26.4k, $184k, $1.23M.
local function short(n)
  if n < 10000 then return money(n) end
  local unit, div = "k", 1000
  if n >= 1000000000 then
    unit, div = "B", 1000000000
  elseif n >= 1000000 then
    unit, div = "M", 1000000
  end
  local whole = n // div
  local frac = (n % div) // (div // 100) -- two decimals, no overflow
  if whole >= 100 then return "$" .. whole .. unit end
  if whole >= 10 then return "$" .. whole .. "." .. (frac // 10) .. unit end
  return "$" .. whole .. "." .. string.format("%02d", frac) .. unit
end

local function wrap(text, width)
  width = width or WRAP
  local out = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      if line == "" then
        line = word
      elseif #line + 1 + #word <= width then
        line = line .. " " .. word
      else
        out[#out + 1] = line
        line = word
      end
    end
    out[#out + 1] = line
  end
  return out
end

-- LEDs ------------------------------------------------------------------------------

local function sirens(on)
  if not led then return end
  if blink then
    timer.cancel(blink)
    blink = nil
  end
  if on then
    local red = true
    blink = timer.every(300, function()
      if red then led.fill(255, 0, 0) else led.fill(0, 0, 255) end
      red = not red
    end)
  else
    led.off()
  end
end

-- Layout ------------------------------------------------------------------------------

local function build()
  hub = { rows = {} }
  hub.city = ui.label(8, 2, "", { size = 14 })
  hub.day = ui.label(160, 2, "", { size = 14, w = 152, align = "right", color = "dim" })
  hub.cash = ui.label(8, 20, "", { size = 20, color = "green" })
  hub.debt = ui.label(160, 20, "", { size = 12, w = 152, align = "right", color = "orange" })
  hub.bank = ui.label(160, 33, "", { size = 12, w = 152, align = "right", color = "dim" })
  ui.rect(0, 48, W, 1, { color = "border" })
  hub.hl = ui.rect(0, LIST_Y, W, ROW_H, { color = "panel" })
  for i = 1, HUB_ROWS do
    local y = LIST_Y + (i - 1) * ROW_H
    hub.rows[i] = {
      qty = ui.label(4, y, "", { size = 14, w = 30, align = "right", color = "dim" }),
      name = ui.label(42, y, "", { size = 14 }),
      price = ui.label(180, y, "", { size = 14, w = 132, align = "right" }),
    }
  end
  ui.rect(0, 180, W, 1, { color = "border" })
  hub.bag = ui.label(8, 184, "", { size = 12 })
  hub.health = ui.label(160, 184, "", { size = 12, w = 152, align = "right" })
  hub.hint = ui.label(0, 201, "", { size = 12, w = W, align = "center", color = "dim" })

  -- A sheet takes the place of the market list.
  view = { rows = {}, rights = {} }
  view.hl = ui.rect(0, LIST_Y, W, ROW_H, { color = "panel" })
  view.title = ui.label(8, LIST_Y, "", { size = 14, color = "lpurple" })
  view.title_right = ui.label(160, LIST_Y, "", { size = 14, w = 152, align = "right" })
  for i = 1, SHEET_ROWS do
    local y = LIST_Y + i * ROW_H
    view.rows[i] = ui.label(8, y, "", { size = 14 })
    view.rights[i] = ui.label(160, y, "", { size = 14, w = 152, align = "right", color = "dim" })
  end
end

local function show_list(on)
  hub.hl:show(on)
  for i = 1, HUB_ROWS do
    hub.rows[i].qty:show(on)
    hub.rows[i].name:show(on)
    hub.rows[i].price:show(on)
  end
end

local function show_view(on)
  view.hl:show(false)
  view.title:show(on)
  view.title_right:show(on)
  for i = 1, SHEET_ROWS do
    view.rows[i]:show(on)
    view.rights[i]:show(on)
  end
end

local function draw_header()
  if not s then
    hub.city:text("")
    hub.day:text("")
    hub.cash:text("")
    hub.debt:text("")
    hub.bank:text("")
    hub.bag:text("")
    hub.health:text("")
    return
  end
  hub.city:text(T.CITIES[s.city])
  hub.day:text(T.day(G.day(s), G.DAYS))
  hub.cash:text(money(s.cash))
  hub.debt:text(T.DEBT_LABEL .. " " .. short(s.debt))
  hub.bank:text(T.BANK_LABEL .. " " .. short(s.bank))
  hub.bag:text(T.bag(s.carry, s.carry_max))
  hub.health:text(T.health(s.health))
end

-- Paints a sheet. lines[i] is a string or { left, right }.
local function paint(title, title_right, lines, selected, hint)
  draw_header()
  view.title:text(title or "")
  view.title_right:text(title_right or "")
  for i = 1, SHEET_ROWS do
    local line = lines[i]
    if type(line) == "table" then
      view.rows[i]:text(line[1] or "")
      view.rights[i]:text(line[2] or "")
    else
      view.rows[i]:text(line or "")
      view.rights[i]:text("")
    end
  end
  if selected then
    view.hl:pos(0, LIST_Y + selected * ROW_H)
    view.hl:show(true)
  else
    view.hl:show(false)
  end
  hub.hint:text(hint or "")
end

local function open(sh)
  mode = "sheet"
  sheet = sh
  show_list(false)
  show_view(true)
  sheet.draw()
end

-- Sheets --------------------------------------------------------------------------------

-- Optional text above up to SHEET_ROWS options. An item is a string or
-- { label, right }. opts.info(sel) adds a line that follows the selection;
-- opts.right is shown next to the title. on_back = nil: BACK does nothing.
local function menu(title, text, items, on_pick, on_back, opts)
  opts = opts or {}
  local sel = 1
  local sh = {}
  function sh.draw()
    local lines = {}
    for i = 1, #text do lines[#lines + 1] = text[i] end
    if opts.info then lines[#lines + 1] = opts.info(sel) end
    local base = #lines
    for i = 1, #items do
      local it = items[i]
      local label, right = it, nil
      if type(it) == "table" then label, right = it[1], it[2] end
      local mark = (i == sel) and "> " or "  "
      lines[base + i] = { mark .. label, right }
    end
    paint(title, opts.right, lines, base + sel, T.HINT_MENU)
  end
  function sh.key(key, rep)
    if key == "up" then
      sel = sel - 1
      if sel < 1 then sel = #items end
      sh.draw()
    elseif key == "down" then
      sel = sel + 1
      if sel > #items then sel = 1 end
      sh.draw()
    elseif key == "select" and not rep then
      on_pick(sel)
    elseif key == "back" and not rep and on_back then
      if on_back == "exit" then return false end -- leave the app
      on_back()
    end
  end
  open(sh)
end

local function ask(title, text, on_yes, on_no)
  menu(title, wrap(text), { T.YES, T.NO }, function(i)
    if i == 1 then on_yes() else on_no() end
  end, on_no)
end

-- Pages of text, one or more texts; any key moves on, then `after` runs.
local function say(title, texts, after)
  local pages, page = {}, {}
  for i = 1, #texts do
    local lines = wrap(texts[i])
    if #page > 0 and #page + 1 + #lines > SHEET_ROWS then
      pages[#pages + 1] = page
      page = {}
    elseif #page > 0 then
      page[#page + 1] = ""
    end
    for j = 1, #lines do
      if #page == SHEET_ROWS then
        pages[#pages + 1] = page
        page = {}
      end
      page[#page + 1] = lines[j]
    end
  end
  if #page > 0 then pages[#pages + 1] = page end
  if #pages == 0 then
    after()
    return
  end

  local n = 1
  local sh = {}
  function sh.draw()
    local right = #pages > 1 and (n .. "/" .. #pages) or nil
    paint(title, right, pages[n], nil, T.HINT_NEXT)
  end
  function sh.key(key, rep)
    if rep then return end
    if key == "left" or key == "up" then
      if n > 1 then
        n = n - 1
        sh.draw()
      end
    elseif n < #pages then
      n = n + 1
      sh.draw()
    else
      after()
    end
  end
  open(sh)
end

-- Digit-by-digit amount, from 0 to max, starting on max.
local function amount(title, max, on_done, on_back)
  local limit = tostring(max)
  local digits, cur = {}, 1
  for i = 1, #limit do digits[i] = limit:sub(i, i) end
  local sh = {}
  function sh.draw()
    local shown = {}
    for i = 1, #digits do
      shown[i] = (i == cur) and ("[" .. digits[i] .. "]") or (" " .. digits[i] .. " ")
    end
    paint(title, money(max), {
      T.HOW_MUCH, "", "$" .. table.concat(shown),
    }, nil, T.HINT_AMOUNT)
  end
  function sh.key(key, rep)
    if key == "left" then
      if cur > 1 then cur = cur - 1 end
    elseif key == "right" then
      if cur < #digits then cur = cur + 1 end
    elseif key == "up" or key == "down" then
      local v = tonumber(digits[cur])
      if key == "up" then v = (v + 1) % 10 else v = (v + 9) % 10 end
      digits[cur] = tostring(v)
      -- Same length strings: comparing text is comparing numbers.
      if table.concat(digits) > limit then
        for i = 1, #digits do digits[i] = limit:sub(i, i) end
      end
    elseif key == "select" then
      if not rep then on_done(tonumber(table.concat(digits)) or 0) end
      return
    elseif key == "back" then
      if not rep then on_back() end
      return
    end
    sh.draw()
  end
  open(sh)
end

-- Game flow -------------------------------------------------------------------------------

local show_hub, title_screen, fight, hub_menu

local function save()
  storage.set("save", s)
end

local function game_over(title)
  sirens(false)
  local score = G.score(s)
  local best = storage.get("best") or 0
  local lines = { money(score) }
  if score > best then
    lines[2] = T.NEW_RECORD
    if best > 0 then lines[3] = T.previous_record(money(best)) end
    best = score
  else
    lines[2] = T.record(money(best))
  end
  storage.set("best", best)
  storage.remove("save")
  local days = G.day(s)
  say(title or T.game_over_days(days), { table.concat(lines, "\n") }, function()
    s = nil
    title_screen()
  end)
end

-- Buy, sell or drop one good.
local function trade(e)
  local held = s.qty[e.id]
  local modes = {}
  if e.price then
    if held > 0 then modes[#modes + 1] = "sell" end
    modes[#modes + 1] = "buy"
  else
    modes[#modes + 1] = "drop"
  end
  local m = 1
  local function max_qty()
    if modes[m] == "buy" then return G.max_buy(s, e.id) end
    return held
  end
  local qty = max_qty()
  if qty == 0 and #modes == 1 then
    ui.toast(T.CANT_BUY_SELL)
    return
  end

  local label = { buy = T.BUY, sell = T.SELL, drop = T.DROP }
  local sh = {}
  function sh.draw()
    local tabs = {}
    for i = 1, #modes do
      local name = label[modes[i]]
      tabs[i] = (i == m) and ("[" .. name .. "]") or (" " .. name .. " ")
    end
    local lines = {
      held > 0 and (T.PURCHASE_PRICE .. money(s.paid[e.id])) or "",
      table.concat(tabs, " "),
      { "< " .. qty .. " >", "/ " .. max_qty() },
      "",
      { label[modes[m]] .. " " .. qty .. " " .. T.GOODS[e.id],
        e.price and money(e.price * qty) or "" },
    }
    paint(T.GOODS[e.id], e.price and money(e.price) or T.NOT_SOLD, lines, nil, T.HINT_TRADE)
  end
  function sh.key(key, rep)
    local step = rep and 10 or 1
    if key == "left" then
      qty = qty - step
      if qty < 0 then qty = 0 end
    elseif key == "right" then
      qty = qty + step
      if qty > max_qty() then qty = max_qty() end
    elseif key == "up" or key == "down" then
      if #modes > 1 and not rep then
        m = (m % #modes) + 1
        qty = max_qty()
      end
    elseif key == "select" then
      if rep then return end
      if qty > 0 then
        if modes[m] == "buy" then
          G.buy(s, e.id, qty)
        elseif modes[m] == "sell" then
          G.sell(s, e.id, qty)
        else
          G.drop(s, e.id, qty)
        end
      end
      show_hub()
      return
    elseif key == "back" then
      if not rep then show_hub() end
      return
    end
    sh.draw()
  end
  open(sh)
end

local function after_kill()
  if G.can_heal(s, true) then
    ask(T.HOSPITAL, T.heal_ask(money(G.HEAL_PRICE)), function()
      G.heal(s)
      show_hub()
    end, show_hub)
  else
    show_hub()
  end
end

-- log: up to two lines about the last round.
fight = function(log)
  log = log or {}
  local cop = s.fight
  local gun = G.best_gun(s)
  local text = {
    T.MY_HEALTH .. ": " .. s.health,
    gun and T.weapon_line(T.GUNS[gun], G.GUNS[gun][3], G.GUNS[gun][4]) or T.NO_WEAPON,
    log[1] or "",
    log[2] or "",
  }
  local items = {}
  if gun then items[#items + 1] = T.STRIKE end
  items[#items + 1] = { T.RUN, T.run_odds(G.ESCAPE_ODDS) }

  menu(T.COPS[cop], text, items, function(i)
    local run = (i == #items)
    local r = run and G.run(s) or G.strike(s)
    save()

    local lines = {}
    if run then
      if r.status == "remain" or r.status == "dead" then lines[1] = T.LOG_CAUGHT_UP end
    elseif r.given then
      lines[1] = T.LOG_HIT .. ": " .. r.given
    else
      lines[1] = T.LOG_MISS
    end
    if r.taken then
      lines[#lines + 1] = r.taken > 0 and (T.LOG_REPLY_HIT .. ": " .. r.taken) or T.LOG_REPLY_MISS
    end

    if r.status == "dead" then
      game_over(T.TITLE_DIED)
    elseif r.status == "escaped" then
      sirens(false)
      say(T.TITLE_ESCAPED, { "" }, show_hub)
    elseif r.status == "caught" then
      sirens(false)
      say(T.TITLE_CAUGHT, { T.FIGHT_CAUGHT }, show_hub)
    elseif r.status == "kill" then
      sirens(false)
      say(T.killed(T.COPS[cop]), {
        lines[1] .. "\n" .. T.reward(money(G.COPS[cop][3])),
      }, after_kill)
    else
      fight(lines)
    end
  end, nil, { right = tostring(s.cops[cop]) })
end

local function start_fight()
  sirens(true)
  fight()
end

-- What happens on arrival: market news, the day's event, an offer, a fight.
local function arrive(ev)
  local news = {}
  for i = 1, #s.market do
    local g = s.market[i]
    if g.ev == 1 then
      news[#news + 1] = T.EXPENSIVE[g.id]
    elseif g.ev == 2 then
      news[#news + 1] = T.CHEAP[g.id]
    end
  end

  local function then_fight()
    if s.fight ~= 0 then start_fight() else show_hub() end
  end

  local offer
  if ev then
    local name = ev.id and T.GOODS[ev.id]
    if ev.type == "friend" then
      news[#news + 1] = T.friend(ev.n, name)
    elseif ev.type == "corpse" then
      news[#news + 1] = T.corpse(ev.n, name)
    elseif ev.type == "mugged" then
      news[#news + 1] = T.mugged(money(ev.cash))
    elseif ev.type == "dogs" then
      news[#news + 1] = T.dogs(ev.n, name)
    elseif ev.type == "coat" then
      offer = function()
        ask(T.EVENTS, T.coat(ev.pockets, money(ev.price)), function()
          if not G.buy_coat(s, ev.pockets, ev.price) then ui.toast(T.NOT_ENOUGH_CASH) end
          show_hub()
        end, show_hub)
      end
    elseif ev.type == "gun" then
      offer = function()
        local price = G.gun_price(ev.kind, true)
        ask(T.EVENTS, T.gun_offer(T.GUNS[ev.kind], money(price)), function()
          if not G.buy_gun(s, ev.kind, true) then ui.toast(T.NOT_ENOUGH_CASH) end
          show_hub()
        end, show_hub)
      end
    end
  end

  say(T.EVENTS, news, offer or then_fight)
end

local function move()
  local items = {}
  for i = 1, #T.CITIES do
    items[i] = { T.CITIES[i], T.CITY_SERVICE[i] }
  end
  menu(T.MOVE, {}, items, function(i)
    if i == s.city then
      ui.toast(T.ALREADY_THERE)
      return
    end
    local ev = G.move(s, i)
    cursor, top = 1, 1
    save()
    arrive(ev)
  end, show_hub)
end

local function finish()
  ask(T.FINISH, T.FINISH .. " ?", function() game_over() end, show_hub)
end

local function gun_shop()
  local items = {}
  for k = 1, #T.GUNS do
    items[k] = { T.GUNS[k], money(G.gun_price(k, false)) }
  end
  menu(T.GUN_SHOP, {}, items, function(k)
    local ok, why = G.buy_gun(s, k, false)
    if ok then
      show_hub()
    elseif why == "cash" then
      ui.toast(T.NOT_ENOUGH_CASH)
    elseif why == "space" then
      ui.toast(T.NOT_ENOUGH_SPACE)
    else
      ui.toast(T.ALREADY_HAS_GUN)
    end
  end, show_hub, {
    info = function(k)
      return T.DAMAGE .. " " .. G.GUNS[k][3] .. "   " .. T.ACCURACY .. " " .. G.GUNS[k][4] .. "%"
    end,
  })
end

local function pay(title, max, empty, apply)
  if max <= 0 then
    ui.toast(empty)
    return
  end
  amount(title, max, function(n)
    apply(s, n)
    show_hub()
  end, show_hub)
end

local function bank()
  menu(T.BANK, { T.BANK_LABEL .. " " .. money(s.bank) }, { T.DEPOSIT, T.WITHDRAW }, function(i)
    if i == 1 then
      pay(T.DEPOSIT, s.cash, T.NOT_ENOUGH_CASH, G.deposit)
    else
      pay(T.WITHDRAW, s.bank, T.NOT_ENOUGH_BANK, G.withdraw)
    end
  end, show_hub)
end

local function instructions(after)
  say(T.INSTRUCTIONS_BTN, T.INSTRUCTIONS, after)
end

-- The city's services, then the general entries.
hub_menu = function()
  local items, actions = {}, {}
  local function entry(label, fn)
    items[#items + 1] = label
    actions[#actions + 1] = fn
  end
  if s.city == G.SHARK_CITY then
    entry({ T.PAY_DEBT, T.LOAN_SHARK }, function()
      pay(T.PAY_DEBT, G.max_pay(s), T.NOT_ENOUGH_CASH, G.pay_debt)
    end)
  end
  if G.has_bank(s) then entry(T.BANK, bank) end
  if s.city == G.GUNS_CITY then entry(T.GUN_SHOP, gun_shop) end
  if s.city == G.HOSPITAL_CITY and s.health < G.HEALTH_MAX then
    entry({ T.HOSPITAL, money(G.HEAL_PRICE) }, function()
      if G.can_heal(s, false) then
        G.heal(s)
        show_hub()
      else
        ui.toast(T.NOT_ENOUGH_CASH)
      end
    end)
  end
  entry(T.INSTRUCTIONS_BTN, function() instructions(show_hub) end)
  entry(T.GIVE_UP, function()
    ask(T.GIVE_UP, T.GIVE_UP_ASK, function() game_over() end, show_hub)
  end)
  menu(T.MENU, {}, items, function(i) actions[i]() end, show_hub)
end

-- Hub: the market --------------------------------------------------------------------------

local function draw_hub()
  draw_header()
  if cursor > #entries then cursor = #entries end
  if cursor < 1 then cursor = 1 end
  if cursor < top then top = cursor end
  if cursor > top + HUB_ROWS - 1 then top = cursor - HUB_ROWS + 1 end
  for i = 1, HUB_ROWS do
    local e = entries[top + i - 1]
    local r = hub.rows[i]
    if e then
      local q = s.qty[e.id]
      r.qty:text(q > 0 and tostring(q) or "")
      r.name:text(T.GOODS[e.id])
      if e.price then
        r.price:text(money(e.price))
        r.price:color(e.ev == 1 and "orange" or (e.ev == 2 and "green" or "text"))
      else
        r.price:text(T.NOT_SOLD)
        r.price:color("dim")
      end
    else
      r.qty:text("")
      r.name:text("")
      r.price:text("")
    end
  end
  hub.hl:pos(0, LIST_Y + (cursor - top) * ROW_H)
  hub.hint:text(s.days_left == 0 and T.HINT_HUB_LAST or T.HINT_HUB)
end

show_hub = function()
  if s.dead then
    game_over(T.TITLE_DIED)
    return
  end
  if s.fight ~= 0 then
    start_fight()
    return
  end
  save()
  entries = {}
  local sold = {}
  for i = 1, #s.market do
    local g = s.market[i]
    entries[#entries + 1] = { id = g.id, price = g.price, ev = g.ev }
    sold[g.id] = true
  end
  for id = 1, #T.GOODS do
    if s.qty[id] > 0 and not sold[id] then
      entries[#entries + 1] = { id = id }
    end
  end
  mode = "hub"
  sheet = nil
  show_view(false)
  show_list(true)
  draw_hub()
end

local function hub_key(key, rep)
  if key == "up" then
    cursor = cursor - 1
    if cursor < 1 then cursor = rep and 1 or #entries end
    draw_hub()
  elseif key == "down" then
    cursor = cursor + 1
    if cursor > #entries then cursor = rep and #entries or 1 end
    draw_hub()
  elseif rep then
    return true
  elseif key == "select" then
    trade(entries[cursor])
  elseif key == "left" then
    hub_menu()
  elseif key == "right" then
    if s.days_left == 0 then finish() else move() end
  elseif key == "back" then
    return false -- leave the app; the game is saved
  end
  return true
end

-- Title ----------------------------------------------------------------------------------------

local function valid(saved)
  return type(saved) == "table" and type(saved.qty) == "table"
    and type(saved.market) == "table" and type(saved.cops) == "table"
    and type(saved.guns) == "table" and #saved.qty == #T.GOODS
    and type(saved.city) == "number" and saved.city <= G.CITIES
end

title_screen = function()
  s = nil
  local saved = storage.get("save")
  local items, actions = {}, {}
  if valid(saved) then
    items[1] = { T.CONTINUE, T.resume_day(G.day(saved), G.DAYS) }
    actions[1] = function()
      s = saved
      cursor, top = 1, 1
      show_hub()
    end
  end
  items[#items + 1] = T.NEW_GAME
  actions[#actions + 1] = function()
    s = G.new()
    cursor, top = 1, 1
    arrive(nil) -- the first market has its news too
  end
  items[#items + 1] = T.INSTRUCTIONS_BTN
  actions[#actions + 1] = function() instructions(title_screen) end
  items[#items + 1] = T.CREDITS_BTN
  actions[#actions + 1] = function() say(T.CREDITS_BTN, T.CREDITS, title_screen) end

  -- The record sits next to the title, once a game has been finished.
  local best = storage.get("best") or 0
  menu(T.APP, {}, items, function(i) actions[i]() end, "exit",
    { right = best > 0 and T.record(money(best)) or nil })
end

-- Splash: the syringe, drawn in characters ------------------------------

local SYRINGE = {
  "    |                      ",
  "|   +---------------------+",
  "|   |             |       |",
  "+===+=============|       |=+--------------",
  "|   |             |       |",
  "|   +---'--'--'-----------+",
  "    |                      ",
}
local ART_W = 43       -- columns, needle included
local BODY_W = 29      -- columns before the needle
local BLOOD_COL = 20   -- first column of the reservoir
local BLOOD_W = 7

local splash

-- The badge's text font is proportional and labels trim their spaces, so the
-- characters are drawn on a canvas instead, each in a 6x9 cell with its own
-- little bitmap shape. Coordinates start at 1 with a spare pixel all round,
-- so the drawing fits whether the canvas counts from 0 or from 1.
local CELL_W, CELL_H, SCALE = 6, 9, 1

local function glyph(c, ch, col, line)
  local x = 1 + (col - 1) * CELL_W
  local y = 1 + (line - 1) * CELL_H
  if ch == "|" then
    c:rect(x + 2, y, 1, 8, "text")
  elseif ch == "-" then
    c:rect(x, y + 4, 5, 1, "text")
  elseif ch == "=" then
    c:rect(x, y + 3, 5, 1, "text")
    c:rect(x, y + 5, 5, 1, "text")
  elseif ch == "+" then
    c:rect(x + 2, y + 2, 1, 5, "text")
    c:rect(x, y + 4, 5, 1, "text")
  elseif ch == "'" then
    c:rect(x + 2, y, 1, 3, "text")
  elseif ch == "#" then
    c:rect(x + 1, y + 1, 1, 7, RED)
    c:rect(x + 3, y + 1, 1, 7, RED)
    c:rect(x, y + 3, 5, 1, RED)
    c:rect(x, y + 5, 5, 1, RED)
  end
end

local function column(c, col)
  for line = 1, #SYRINGE do
    glyph(c, SYRINGE[line]:sub(col, col), col, line)
  end
end

local function start_splash()
  splash = { step = 0 }
  local cw, ch = ART_W * CELL_W + 2, #SYRINGE * CELL_H + 2
  local ok, canvas = pcall(ui.canvas, (W - cw * SCALE) // 2, 30, cw, ch,
    { scale = SCALE, color = "bg" })
  if ok then splash.canvas = canvas end
  splash.name = ui.label(0, 126, "", { size = 32, w = W, align = "center" })
  splash.hint = ui.label(0, 196, "", { size = 12, w = W, align = "center", color = "dim" })

  -- The outline is traced, the reservoir fills, then the needle comes out.
  local function draw(n)
    local c = splash.canvas
    if n <= BODY_W then
      column(c, n)
    elseif n <= BODY_W + BLOOD_W then
      local col = BLOOD_COL + (n - BODY_W) - 1
      for line = 3, 5 do glyph(c, "#", col, line) end
    else
      column(c, n - BLOOD_W)
    end
  end

  local last = ART_W + BLOOD_W
  splash.timer = timer.every(40, function()
    local n = splash.step + 1
    splash.step = n
    if n <= last and splash.canvas then
      -- A canvas that does not behave as documented costs the drawing, not the game.
      if not pcall(draw, n) then
        pcall(splash.canvas.remove, splash.canvas)
        splash.canvas = nil
      end
    else
      timer.cancel(splash.timer)
      splash.timer = nil
      splash.name:text(T.APP)
      splash.hint:text(T.HINT_SPLASH)
    end
  end)
end

local function end_splash()
  if splash.timer then timer.cancel(splash.timer) end
  if splash.canvas then pcall(splash.canvas.remove, splash.canvas) end
  splash.name:remove()
  splash.hint:remove()
  splash = nil
  build()
  title_screen()
end

-- Callbacks ---------------------------------------------------------------------------------------

function on_key(key, rep)
  if mode == "splash" then
    if not rep then end_splash() end
    return true
  end
  if mode == "hub" then
    return hub_key(key, rep)
  end
  return sheet.key(key, rep) ~= false
end

function on_exit()
  sirens(false)
end

start_splash()
