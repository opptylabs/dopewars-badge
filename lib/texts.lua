-- Every string shown by the game.

local T = {}

T.APP = "DOPEWARS"

T.GOODS = {
  "Acid", "Cocaine", "Hashish", "Heroin", "Ludes", "MDA", "Opium", "PCP",
  "Peyote", "Shrooms", "Speed", "Weed",
}

T.CHEAP = {
  [1] = "The market is flooded with cheap home-made acid!",
  [3] = "The Marrakesh Express has arrived!",
  [5] = "Rival drug dealers raided a pharmacy and are selling cheap ludes!",
  [12] = "Columbian freighter dusted the Coast Guard! Weed prices have bottomed out!",
}

T.EXPENSIVE = {
  [2] = "Cops made a big Cocaine bust! Prices are outrageous!",
  [4] = "Cops made a big Heroin bust! Prices are outrageous!",
  [7] = "Addicts are buying Opium at ridiculous prices!",
  [11] = "Addicts are buying Speed at ridiculous prices!",
}

-- Short names: they share a row with the day or with the service.
T.CITIES = {
  "Olympia", "King's Cross", "Waterloo", "Victoria", "Tottenham Ct Rd",
  "Liverpool St",
}
-- What each station offers, shown next to its name.
T.CITY_SERVICE = { "Loan Shark", "Guns", "Hospital", "Bank", "", "Bank" }

T.GUNS = { "Baretta", ".38 Special", "Ruger", "Saturday Night Special" }
T.COPS = { "Officer Hardass", "Officer Bob", "Agent Smith" }

-- Menus and buttons
T.NEW_GAME = "New Game"
T.CONTINUE = "Continue Game"
T.INSTRUCTIONS_BTN = "Instructions"
T.CREDITS_BTN = "Credits"
T.GIVE_UP = "Give Up"
T.GIVE_UP_ASK = "Give Up ?"
T.MOVE = "Move"
T.FINISH = "Finish"
T.LOAN_SHARK = "Loan Shark"
T.PAY_DEBT = "Pay debt"
T.BANK = "Bank"
T.DEPOSIT = "Deposit"
T.WITHDRAW = "Withdraw"
T.GUN_SHOP = "Dan's House of Guns"
T.HOSPITAL = "Hospital"
T.BUY = "Buy"
T.SELL = "Sell"
T.DROP = "Drop"
T.YES = "Yes"
T.NO = "No"
T.EVENTS = "Events"
T.STRIKE = "Strike"
T.RUN = "Run"
T.MENU = "Menu"

-- Status
T.DEBT_LABEL = "DEBT"
T.BANK_LABEL = "BANK"
T.DAMAGE = "Damage"
T.ACCURACY = "Accuracy"
T.NOT_SOLD = "Not sold here"
T.PURCHASE_PRICE = "Purchase price : "
T.MY_HEALTH = "My health"

function T.resume_day(day, total) return "Day " .. day .. " of " .. total end
function T.day(day, total) return "Day " .. day .. "/" .. total end
function T.bag(n, max) return "Bag " .. n .. "/" .. max end
function T.health(n) return "Health " .. n end
function T.heal_ask(price) return "Heal for " .. price .. " ?" end
function T.game_over_days(n) return "Game over - " .. n .. " days" end
T.NEW_RECORD = "New record"
function T.record(score) return "Record " .. score end
function T.previous_record(score) return "Previous record " .. score end

-- Errors
T.ALREADY_THERE = "Where do you wanna go ?"
T.NOT_ENOUGH_CASH = "Not enough cash..."
T.NOT_ENOUGH_BANK = "Not enough in the bank..."
T.NOT_ENOUGH_SPACE = "Not enough space..."
T.ALREADY_HAS_GUN = "Already has this gun..."
T.CANT_BUY_SELL = "Can't buy or sell..."
T.HOW_MUCH = "How much ?"

-- Random events
local function packets(n)
  if n == 1 then return "1 packet" end
  return n .. " packets"
end

function T.friend(n, good)
  return "You bump into a friend from Breakpoint! He gives you " .. packets(n) ..
    " of " .. good .. "."
end

function T.corpse(n, good)
  return "You find " .. packets(n) .. " of " .. good .. " on a dead dude on the Tube!"
end

function T.mugged(cash)
  return "You were mugged on the Tube! You lost " .. cash .. "!"
end

function T.dogs(n, good)
  return "Police dogs chase you! You dropped " .. packets(n) .. " of " .. good ..
    "! That's a drag, man!"
end

function T.coat(pockets, price)
  return "Buy " .. pockets .. " extra pockets for " .. price .. " ?"
end

function T.gun_offer(name, price)
  return "Buy a " .. name .. " for " .. price .. " ?"
end

-- Fights
T.FIGHT_CAUGHT = "You ran into a dead end, and the cops found you. The cops " ..
  "seized all your dope and half your cash."
T.NO_WEAPON = "You have no gun."
T.TITLE_ESCAPED = "You lost him"
T.TITLE_CAUGHT = "Cornered"
T.TITLE_DIED = "You're dead"
T.LOG_HIT = "You hit him"
T.LOG_MISS = "You miss."
T.LOG_REPLY_HIT = "He fires back"
T.LOG_REPLY_MISS = "He misses you."
T.LOG_CAUGHT_UP = "He catches up with you."

function T.weapon_line(name, dmg, precision)
  return name .. ": " .. dmg .. " dmg, " .. precision .. "%"
end

function T.run_odds(odds) return odds .. "% to lose him" end
function T.killed(name) return name .. " is dead" end
function T.reward(cash) return "You pick up " .. cash .. "." end

T.INSTRUCTIONS = {
  "Breakpoint 2026 is in town, and you are a drug dealer working the London " ..
  "Underground. You travel between six stations: Kensington (Olympia), right " ..
  "by the conference, King's Cross St Pancras, Waterloo, Victoria, Tottenham " ..
  "Court Road and Liverpool Street. You buy " ..
  "and sell various drugs such as Cocaine, Heroin, Acid, Weed, Speed and " ..
  "Ludes. Each trip on the Tube takes one day. The point of the game is to " ..
  "make the most amount of money in the given time of 30 days.",
  "You begin at Olympia with $2,000 and a $5,500 debt. You must quickly pay " ..
  "back the loan shark, who waits for you at Olympia, because the debt is " ..
  "growing by 10% each day. Guns are sold at King's Cross, the hospital is " ..
  "at Waterloo, and the bank, which pays 5% a day, has branches at Victoria " ..
  "and Liverpool Street.",
  "During the game, Officer Hardass will randomly confront you. You have " ..
  "two choices: to run or to fight. Any choice risks injury you and after " ..
  "a few shots you die and thus lose the game. In order to fight the " ..
  "police, you must have a gun. If you can kill Hardass, you'll get a cash " ..
  "award. Random occurrences also occur during the game such as muggings, " ..
  "drug sales, increased drug prices, and the finding of drugs.",
  "After 30 days, the game ends. The final score is calculated by adding " ..
  "your current amount of cash and bank, and subtracting the double of " ..
  "your debt. For example, if you finish with $1,000,000 cash, $1,000,000 " ..
  "bank, and $300,000 debt, you will have a final score of $1,400,000.",
}

T.CREDITS = {
  "Original Game by John E. Dell in 1984",
  "Produced by @0xOppty",
  "Also available on Android and the App Store",
}

-- Key hints (badge only)
T.HINT_SPLASH = "press a key"
T.HINT_HUB = "< Menu      OK Trade      Move >"
T.HINT_HUB_LAST = "< Menu      OK Trade      Finish >"
T.HINT_MENU = "OK select      BACK cancel"
T.HINT_NEXT = "OK"
T.HINT_TRADE = "< > qty     ^ v mode     OK"
T.HINT_AMOUNT = "< > digit     ^ v change     OK"

return T
