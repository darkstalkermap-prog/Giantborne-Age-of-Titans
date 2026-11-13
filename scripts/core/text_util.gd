class_name TextUtil
extends RefCounted
## M9 gate (lane review): the words the game writes round a display name. Many names begin with "The" (The Iron
## Regiment, The Giantforge, The Kings' Annals, The Broken Stair); written mid-sentence they read "until The Iron
## Regiment is beaten" or "Take the The Kings' Annals". Pure, no state.


## A display name as it reads mid-sentence: a leading "The " lower-cased ("until the Iron Regiment is beaten"),
## any other name as it is ("by Kingsgate ramp"). It only lower-cases - with_the() also gives a name its "the".
static func mid_sentence(display_name: String) -> String:
	if display_name.begins_with("The "):
		return "the " + display_name.substr(4)
	return display_name


## A display name after a "the" the sentence wants: "the Giantforge" for "The Giantforge" and for "Giantforge"
## alike ("Reforge at the Giantforge", "You wake at the Broken Stair"). TitleScreen.mid_sentence's rule.
static func with_the(display_name: String) -> String:
	if display_name.begins_with("The "):
		return "the " + display_name.substr(4)
	return "the " + display_name
