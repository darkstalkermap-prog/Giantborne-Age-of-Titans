class_name ActTwo
extends RefCounted
## Act one ends at the Stone Throne; act two begins (C1, decisions C1-10..C1-12). Pure rules over the world's flags,
## the pledge table and the save's act; GameSession plays the finale and calls begin().
##
##   * campaign.completed (the Stone Throne taken: quest.world_main, every ending branch - Harrok slain, spared or
##     yielded, any oaths) is act one's end. During play it opens the act-one finale (cutscene.act_one_finale, 28 s,
##     skippable), then act two begins and the campaign's end screen shows once, as "Act One" with Continue
##     (decision C1-10). A save that holds campaign.completed without act.two.begun (a 0.14 or 0.15 game, or a quit
##     during the finale) plays the finale on its first Continue in the world and begins act two after it, without the
##     end screen (that game saw it).
##   * begin(): act.two.begun, and each pledge of pledge_table.act_two answered once from the flags as they stand
##     (pledge.<id> = "sends" | "refuses", with pledge.<id>.sends / .refuses): what each act-one settlement does now
##     the rim has broken. The save's act follows (ExpansionState.sync_from_flags: act 2 once act.two.begun).
##   * Without cutscenes (tool runs, headless, --no-cutscenes) act two begins at once.
## Nothing of act one is taken back: its quests, titans and settlements play on.

const COMPLETED_FLAG := "campaign.completed"
const BEGUN_FLAG := "act.two.begun"
const FINALE_ID := "cutscene.act_one_finale"
const TABLE_ID := "pledge_table.act_two"
const MAIN_QUEST := "quest.act_two_main"
const SENDS := "sends"
const REFUSES := "refuses"


## True once act one has ended (the throne taken).
static func act_one_done(flags: Dictionary) -> bool:
	return QuestConditions.truthy(flags.get(COMPLETED_FLAG))


## True once act two has begun.
static func begun(flags: Dictionary) -> bool:
	return QuestConditions.truthy(flags.get(BEGUN_FLAG))


## True when act one is done and act two has not begun: the finale (or its quiet start) is due.
static func due(flags: Dictionary) -> bool:
	return act_one_done(flags) and not begun(flags)


## The pledges of the table ([] without one).
static func pledges() -> Array:
	var rec := GameData.get_record(TABLE_ID)
	var list: Variant = rec.get("pledges", [])
	return list if typeof(list) == TYPE_ARRAY else []


## What a pledge answers in the quest context `ctx`: SENDS when its sends_when holds, else REFUSES.
static func answer(pledge: Dictionary, ctx: Dictionary) -> String:
	var cond: Variant = pledge.get("sends_when", {})
	return SENDS if typeof(cond) == TYPE_DICTIONARY and QuestConditions.holds(cond, ctx) else REFUSES


## Every pledge's answer: {pledge id: sends | refuses}.
static func answers(ctx: Dictionary) -> Dictionary:
	var out := {}
	for p: Dictionary in pledges():
		out[str(p.id)] = answer(p, ctx)
	return out


## The line a pledge speaks for its answer.
static func line_for(pledge: Dictionary, ans: String) -> String:
	return str(pledge.get("sends_line" if ans == SENDS else "refuses_line", ""))


## Begins act two: each pledge answered and its flags set (first write wins: a pledge never changes once given),
## then act.two.begun. `set_flag` is WorldState.try_set_flag-shaped (id, value) -> bool; `ctx` the quest context.
## Returns the answers given now ({} when act two had begun already).
static func begin(set_flag: Callable, ctx: Dictionary) -> Dictionary:
	var flags: Dictionary = ctx.get("flags", {})
	if begun(flags):
		return {}
	var out := answers(ctx)
	for p: Dictionary in pledges():
		var ans := str(out.get(str(p.id), REFUSES))
		set_flag.call(str(p.flag), ans)
		set_flag.call("%s.%s" % [str(p.flag), ans], true)
	set_flag.call(BEGUN_FLAG, true)
	return out


## Fix (council): a game whose act two has begun but whose pledge is missing a valid answer (a flag cleared, a pledge the
## table gained after its start) answers it now from the flags as they stand - else the rim council's line for it offers
## no choice but Leave and its stage can never be heard. Never changes a given answer. Returns {pledge id: answer} set now.
static func answer_missing(set_flag: Callable, ctx: Dictionary) -> Dictionary:
	var flags: Dictionary = ctx.get("flags", {})
	var out := {}
	if not begun(flags):
		return out
	for p: Dictionary in pledges():
		var have := str(flags.get(str(p.flag), ""))
		if have == SENDS or have == REFUSES:
			continue
		var ans := answer(p, ctx)
		set_flag.call(str(p.flag), ans)
		set_flag.call("%s.%s" % [str(p.flag), ans], true)
		out[str(p.id)] = ans
	return out


## Every flag act two's start writes (the content tests' writers): act.two.begun and each pledge's three.
static func written_flags() -> Dictionary:
	var out := {BEGUN_FLAG: true}
	for p: Dictionary in pledges():
		out[str(p.flag)] = true
		out["%s.%s" % [str(p.flag), SENDS]] = true
		out["%s.%s" % [str(p.flag), REFUSES]] = true
	return out
