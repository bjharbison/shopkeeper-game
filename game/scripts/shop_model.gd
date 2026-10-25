class_name ShopModel
extends RefCounted

## The customer loop as pure, screen-free state — the rules of the game with no
## sprites, tweens, or SceneTree. shop.gd (the Node) drives a ShopModel and draws
## whatever it reports; the headless tests drive the SAME ShopModel and assert on
## what it reports. That split is what makes "a full round", "wrong item is not
## penalized", and "ten rounds reach closing time" checkable without a window.
##
## The whole design is forgiving by construction (see docs/DESIGN.md): there is
## no timer, no score that falls, and no fail state. A wrong item only makes the
## customer ask again. The single ending is "closing time" after a fixed number
## of SUCCESSFUL deliveries.

## The shop's stock. Placeholder art exists for each of these (Phase 3 art swaps
## in; the ids stay). Order and membership on the shelf are chosen from this pool.
const ITEM_POOL := ["apple", "bread", "teddy", "balloon", "flower", "fish", "cake", "hat"]

var shelf: Array[String] = []        ## item id per slot; size == items_on_shelf
var till: int = 0                    ## coins earned == successful deliveries
var round_index: int = 0             ## completed (successful) rounds so far

var rounds_total: int = 10
var items_on_shelf: int = 6
var _hint_glow: bool = true
var _hint_rounds: int = 3
var _shuffle_every: int = 3

var _order_slot: int = -1            ## slot holding what the customer asked for
var _wrong_attempts: int = 0         ## wrong tries on the CURRENT customer
var _rng := RandomNumberGenerator.new()


## seed_val > 0 makes item choice deterministic (tests pass a fixed seed); 0 means
## randomize so real play differs each session.
func _init(config: GameConfig = null, seed_val: int = 0) -> void:
	if config != null:
		rounds_total = config.rounds_per_session
		items_on_shelf = config.items_on_shelf
		_hint_glow = config.hint_glow
		_hint_rounds = config.hint_rounds
		_shuffle_every = config.shuffle_every
	if seed_val > 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()


## Stock the shelf with distinct items and bring in the first customer.
func start() -> void:
	till = 0
	round_index = 0
	var pool := ITEM_POOL.duplicate()
	_shuffle(pool)
	var n := clampi(items_on_shelf, 1, pool.size())
	shelf = []
	for i in n:
		shelf.append(pool[i])
	items_on_shelf = n
	new_customer()


## Choose the current order. forced_slot >= 0 pins it (tests); otherwise random.
func new_customer(forced_slot: int = -1) -> void:
	_wrong_attempts = 0
	if forced_slot >= 0 and forced_slot < shelf.size():
		_order_slot = forced_slot
	else:
		_order_slot = _rng.randi_range(0, shelf.size() - 1)


## Hand slot_index to the customer. Returns "correct" or "wrong".
##   correct → till +1, advance a round, maybe reshuffle, bring the next customer
##             (unless it is now closing time).
##   wrong   → nothing is taken away; same customer stays and asks again.
func deliver(slot_index: int) -> String:
	if is_closing():
		return "wrong"
	if slot_index == _order_slot:
		till += 1
		round_index += 1
		if not is_closing():
			if _shuffle_every > 0 and round_index % _shuffle_every == 0:
				_reshuffle_shelf()
			new_customer()
		return "correct"
	else:
		_wrong_attempts += 1
		return "wrong"


func is_closing() -> bool:
	return round_index >= rounds_total


## The item the customer wants, and where it currently sits.
func order_slot() -> int:
	return _order_slot


func order_item() -> String:
	return shelf[_order_slot] if _order_slot >= 0 and _order_slot < shelf.size() else ""


func shelf_item(i: int) -> String:
	return shelf[i] if i >= 0 and i < shelf.size() else ""


func wrong_attempts() -> int:
	return _wrong_attempts


## Glow the correct item? On for the opening rounds only, then training wheels off.
func should_hint() -> bool:
	return _hint_glow and round_index < _hint_rounds


func _reshuffle_shelf() -> void:
	# Permute positions but keep the same set of items, then re-aim the order at
	# whatever slot now holds the wanted item (membership is unchanged).
	var wanted := order_item()
	_shuffle(shelf)
	_order_slot = shelf.find(wanted)
	if _order_slot < 0:
		_order_slot = 0


func _shuffle(arr: Array) -> void:
	# Fisher–Yates with our seeded RNG, so a fixed seed gives a fixed layout.
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
