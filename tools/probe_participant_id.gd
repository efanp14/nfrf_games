extends Node
## Throwaway verification for ParticipantId. Run as a SCENE, not with --script:
## a --script run does not register autoloads, and DataLogger is one.
##
##   godot --headless res://tools/probe_participant_id.tscn

var _failures: int = 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	_check_characters_verify(rng)
	_substitutions_caught(rng)
	_transpositions_caught(rng)
	_normalisation_round_trips()
	_existing_ids_untouched()
	_machine_letter_setting()
	_generation_is_unique()

	print("")
	print("FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(what: String) -> void:
	_failures += 1
	print("  FAIL  %s" % what)


func _random_id(rng: RandomNumberGenerator) -> String:
	while true:
		var body := ParticipantId.LETTERS[rng.randi_range(0, ParticipantId.LETTERS.length() - 1)]
		for _i in range(ParticipantId.RANDOM_LEN):
			body += ParticipantId.ALPHABET[rng.randi_range(0, ParticipantId.ALPHABET.length() - 1)]
		var check := ParticipantId._check_char(body)
		if not check.is_empty():
			return body + check
	return ""


func _check_characters_verify(rng: RandomNumberGenerator) -> void:
	var n := 10000
	var bad := 0
	for _i in range(n):
		if not ParticipantId.check_passes(_random_id(rng)):
			bad += 1
	print("Self-verification: %d/%d valid" % [n - bad, n])
	if bad > 0:
		_fail("%d generated IDs did not pass their own check" % bad)


func _substitutions_caught(rng: RandomNumberGenerator) -> void:
	var tested := 0
	var missed := 0
	for _i in range(2000):
		var id := _random_id(rng)
		for pos in range(ParticipantId.TOTAL_LEN):
			for c in ParticipantId.ALPHABET:
				if c == id[pos]:
					continue
				var mutated := id.substr(0, pos) + c + id.substr(pos + 1)
				tested += 1
				if ParticipantId.check_passes(mutated):
					missed += 1
	print("Single substitutions: %d tested, %d slipped through" % [tested, missed])
	if missed > 0:
		_fail("a single wrong character was accepted")


func _transpositions_caught(rng: RandomNumberGenerator) -> void:
	var tested := 0
	var missed := 0
	var missed_at_check := 0
	for _i in range(4000):
		var id := _random_id(rng)
		for pos in range(ParticipantId.TOTAL_LEN - 1):
			if id[pos] == id[pos + 1]:
				continue
			var swapped := id.substr(0, pos) + id[pos + 1] + id[pos] + id.substr(pos + 2)
			tested += 1
			if ParticipantId.check_passes(swapped):
				missed += 1
				if pos == ParticipantId.TOTAL_LEN - 2:
					missed_at_check += 1
	# Including the swap of the last body character with the check character,
	# which measured 0 in 16,770 and is 0 by algebra: that swap leaves the check
	# unmoved only when the two characters are equal, which is not a swap.
	print("Adjacent transpositions: %d tested, %d slipped through (%d at the check)"
			% [tested, missed, missed_at_check])
	if missed > 0:
		_fail("a transposition was accepted")


func _normalisation_round_trips() -> void:
	# Every way a card might be written or read back must land on one string.
	var canonical := "A7K2Q9"
	var written := ["A7K2Q9", "a7k2q9", "A7K-2Q9", "a7k-2q9", " A7K-2Q9 ", "A7K 2Q9"]
	for form: String in written:
		if ParticipantId.normalize(form) != canonical:
			_fail("%s normalised to %s, not %s" % [form,
					ParticipantId.normalize(form), canonical])
	# The misread pairs the alphabet exists to absorb.
	if ParticipantId.normalize("AIK") != "A1K":
		_fail("I did not fold to 1")
	if ParticipantId.normalize("ALK") != "A1K":
		_fail("L did not fold to 1")
	if ParticipantId.normalize("AOK") != "A0K":
		_fail("O did not fold to 0")
	print("Normalisation: %d written forms all reach %s" % [written.size(), canonical])


func _existing_ids_untouched() -> void:
	# The IDs already in the data must pass through exactly as typed, or the
	# sessions recorded under them are orphaned.
	for old: String in ["p001", "t01", "H1", "pilot_3", "P001"]:
		if ParticipantId.canonical_or_verbatim(old) != old:
			_fail("%s was rewritten to %s" % [old,
					ParticipantId.canonical_or_verbatim(old)])
		if ParticipantId.has_scheme_shape(old) and not ParticipantId.looks_generated(old):
			print("  note: %s has the issued-ID shape and would draw a warning" % old)
	print("Older IDs: 5 passed through unchanged")


## The letter can be pinned by hand, which is what makes two machines unable to
## issue the same ID, and nothing outside the alphabet may be accepted.
func _machine_letter_setting() -> void:
	var original := ParticipantId.machine_letter()

	if not ParticipantId.set_machine_letter("B"):
		_fail("B was refused")
	if ParticipantId.machine_letter() != "B":
		_fail("B did not persist")
	# Lower case and padding are how a letter would actually be typed.
	if not ParticipantId.set_machine_letter(" c "):
		_fail("a padded lowercase letter was refused")
	if ParticipantId.machine_letter() != "C":
		_fail("the padded letter did not normalise to C")

	for bad: String in ["I", "L", "O", "U", "7", "", "AB", "-"]:
		if ParticipantId.set_machine_letter(bad):
			_fail("'%s' was accepted as a machine letter" % bad)
	if ParticipantId.machine_letter() != "C":
		_fail("a rejected letter changed the stored one")
	print("Machine letter: set, normalised, and 8 invalid values refused")

	ParticipantId.set_machine_letter(original)
	if ParticipantId.machine_letter() != original:
		_fail("could not put the original letter back")


## generate() must not hand out something the roster already holds. Runs against
## the real roster path, so it is saved and put back.
func _generation_is_unique() -> void:
	var backup := ""
	var had_roster := FileAccess.file_exists(ParticipantId.ROSTER_PATH)
	if had_roster:
		var f := FileAccess.open(ParticipantId.ROSTER_PATH, FileAccess.READ)
		if f != null:
			backup = f.get_as_text()
			f.close()

	var seen := {}
	var repeats := 0
	for _i in range(120):
		var id := ParticipantId.generate()
		if id.is_empty():
			_fail("generate() gave up")
			break
		if seen.has(id):
			repeats += 1
		seen[id] = true
		ParticipantId.issue(id)

	var roster := ParticipantId.roster_ids()
	print("Generation: %d issued, %d distinct, %d read back from the roster"
			% [seen.size() + repeats, seen.size(), roster.size()])
	if repeats > 0:
		_fail("generate() returned an ID it had already issued %d times" % repeats)
	if roster.size() < seen.size():
		_fail("the roster lost IDs: %d written, %d read back" % [seen.size(), roster.size()])

	var letter := ParticipantId.machine_letter()
	for id: String in seen.keys():
		if not id.begins_with(letter):
			_fail("%s does not start with this machine's letter %s" % [id, letter])
			break
	print("  machine letter: %s" % letter)

	if had_roster:
		var w := FileAccess.open(ParticipantId.ROSTER_PATH, FileAccess.WRITE)
		if w != null:
			w.store_string(backup)
			w.close()
	else:
		DirAccess.remove_absolute(ParticipantId.ROSTER_PATH)
