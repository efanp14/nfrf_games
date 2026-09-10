class_name ParticipantId
## ParticipantId.gd
## Issues the short identifier a participant carries between machines, and
## checks one that has been typed back in.
##
## Why this exists: a person plays T1 and T2 on the solo machine and T3 on the
## group machine, days apart, and the participant ID is the only thing joining
## those sessions together (tools/aggregate_logs.py builds participants_wide.csv
## on it). Until now the ID was invented by hand, so uniqueness rested on the
## research team's bookkeeping, and an ID mistyped at the group machine produced
## a perfectly valid identifier belonging to nobody: the session recorded
## normally and that person's individual sessions silently never joined to it.
##
## The shape is six characters, shown as A7K-2Q9 and stored as A7K2Q9:
##
##   [machine letter][4 random][check character]
##
## COLLISION IS NOT THE INTERESTING RISK. Around a hundred participants against
## a million combinations per machine is already remote, and generate() consults
## what has already been issued before handing one out, which makes a repeat on
## this machine impossible by construction rather than merely unlikely.
## TRANSCRIPTION is the risk, because the ID travels between machines on a slip
## of paper. Hence the check character, which catches every single-character
## substitution and every adjacent transposition at the moment the ID is typed,
## and hence the alphabet below.
##
## NO TIMESTAMP IN THE STRING. It was considered and deliberately left out: the
## ID is a filename and a join key, so two strings differing only by a timestamp
## are two different people everywhere downstream, and trimming one off at parse
## time would mean ParticipantStore, DataLogger and aggregate_logs.py all
## implementing the same rule with nothing raising an error if one of them
## forgot. The moment an ID was issued is recorded in the roster instead, where
## it can settle any question after the fact and nobody has to type it.

## Crockford Base32: the digits and the letters, minus I, L, O and U. The first
## three go because they are the pairs people actually confuse in handwriting
## (I against 1, O against 0), and normalize() folds them back rather than
## rejecting them. U goes because a random string containing it eventually
## spells something a participant should not be handed.
const ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

## The machine letter is drawn from the letters only, so the leading character
## says at a glance that this is a generated ID rather than a hand-typed one.
const LETTERS: String = "ABCDEFGHJKMNPQRSTVWXYZ"

const RANDOM_LEN: int = 4
## Machine letter, the random body, and the check character.
const TOTAL_LEN: int = 1 + RANDOM_LEN + 1
## Where the cosmetic hyphen goes in the displayed form.
const DISPLAY_SPLIT: int = 3

## Generation gives up rather than looping forever if the space is somehow
## exhausted, which cannot happen with a hundred participants but would
## otherwise hang the menu if the roster were ever corrupt.
const MAX_ATTEMPTS: int = 200

## Which machine issued an ID. Derived from the device rather than drawn at
## random so that reinstalling the game, or clearing user://, does not silently
## start issuing IDs from a second letter as though it were a second machine.
const MACHINE_LETTER_PATH: String = "user://machine_letter.txt"

## Every ID this machine has handed out, in the order it handed them out.
##
## Lives beside the session folders rather than inside one, for the same reason
## the replay output does: it is not session data, and both
## DataLogger._verify_codebook_coverage() and tools/check_session.py report a
## file a session folder does not describe. The aggregator ignores it, filtering
## on directories at that level.
const ROSTER_PATH: String = DataLogger.SESSIONS_ROOT + "participant_ids.txt"

## Written once, when the file is created.
##
## The file sits in a folder a researcher opens to collect data, next to things
## they are meant to copy and clear out, and an undated list of codes is exactly
## the sort of file someone tidies away. Deleting it mid-study is the one action
## that weakens the no-repeat guarantee, so the file says so itself rather than
## relying on that being remembered from a document.
##
## Prose lines are ignored on read: roster_ids() keeps only lines shaped like an
## ID, so this cannot be mistaken for one.
const ROSTER_HEADER: String = """CycleCity: participant IDs issued on this machine, newest last.
Each entry is the ID on one line and the moment it was issued on the next.

DO NOT DELETE OR EDIT THIS FILE WHILE THE STUDY IS RUNNING.
The game reads it back before issuing an ID, so that no participant is ever
given one that has been handed out before.

"""


## A new ID that nothing on this machine has used before, or "" if one could not
## be found. Callers must handle the empty string: silently continuing with a
## blank participant ID is exactly the failure this file exists to prevent.
##
## Its own RandomNumberGenerator, never the shared one. Two reasons, both real:
## the project seeds its RNG for reproducible routing (guardrail 3) and drawing
## from it here would disturb that, and a seeded stream would make every install
## issue the identical sequence of IDs.
static func generate() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var letter := machine_letter()
	var taken := _taken_ids()
	for _attempt in range(MAX_ATTEMPTS):
		var body := letter
		for _i in range(RANDOM_LEN):
			body += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
		var check := _check_char(body)
		# Five residues in thirty-seven have no character to write them, so
		# roughly one body in seven is redrawn rather than issued.
		if check.is_empty():
			continue
		var candidate := body + check
		if not taken.has(candidate):
			return candidate
	push_warning("ParticipantId: could not find an unused ID in %d attempts." % MAX_ATTEMPTS)
	return ""


## Records that an ID has been handed out. Called at the moment it is generated,
## NOT when the session starts, because the case this protects against is a card
## written out for a participant who then never plays: the ID is spent either
## way, and reissuing it later would merge two people.
static func issue(participant_id: String) -> void:
	var canonical := normalize(participant_id)
	if canonical.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(DataLogger.SESSIONS_ROOT)
	var file: FileAccess
	if FileAccess.file_exists(ROSTER_PATH):
		file = FileAccess.open(ROSTER_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(ROSTER_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(ROSTER_HEADER)
	if file == null:
		push_warning("ParticipantId: could not write the roster at %s" % ROSTER_PATH)
		return
	# The ID on its own line and the time it was issued on the line below it.
	# Plain text because its one job is to be read by a person looking for an ID
	# whose card has been lost.
	file.store_string("%s\n%s\n\n" % [format_for_display(canonical), _now_utc()])
	file.close()


## Uppercased, with the cosmetic separators removed and the two classic
## misreadings folded back: I and L are 1, O is 0. A card read as "AIK" and one
## read as "A1K" therefore reach the same participant rather than two.
##
## Pure text handling. It says nothing about whether the result is a valid ID,
## which is what check_passes() is for, and callers must not apply it blindly to
## an ID that did not come from here (see canonical_or_verbatim).
static func normalize(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_upper():
		if c == "-" or c == " ":
			continue
		elif c == "I" or c == "L":
			out += "1"
		elif c == "O":
			out += "0"
		else:
			out += c
	return out


## Whether a string has the right length and alphabet to be one of ours. Says
## nothing about whether it is intact; that is check_passes().
static func has_scheme_shape(text: String) -> bool:
	var canonical := normalize(text)
	if canonical.length() != TOTAL_LEN:
		return false
	for c in canonical:
		if not ALPHABET.contains(c):
			return false
	return true


## Whether the check character agrees with the rest of the ID.
static func check_passes(text: String) -> bool:
	if not has_scheme_shape(text):
		return false
	var canonical := normalize(text)
	var body := canonical.substr(0, TOTAL_LEN - 1)
	return canonical[TOTAL_LEN - 1] == _check_char(body)


## A generated ID, intact. The test the menu uses to decide whether it is
## looking at one of ours or at an ID the research team invented themselves.
static func looks_generated(text: String) -> bool:
	return check_passes(text)


## The canonical form for a generated ID, and the typed text untouched for
## anything else.
##
## The condition matters. IDs already in use are shapes like p001 and t01, and
## uppercasing one of those would change the join key and orphan the sessions
## already recorded under it. Normalizing only what verifies as ours means the
## older scheme passes through exactly as typed. A hand-made six-character ID
## whose check character happens to agree is the one exposure, at one chance in
## thirty-two, and it is uppercased rather than damaged.
static func canonical_or_verbatim(text: String) -> String:
	var trimmed := text.strip_edges()
	return normalize(trimmed) if looks_generated(trimmed) else trimmed


## A7K2Q9 shown as A7K-2Q9. Grouping is for reading and writing down, not for
## storage: what reaches the log is the canonical form, and normalize() strips
## the hyphen again on the way back in, so a card written either way works.
static func format_for_display(participant_id: String) -> String:
	var canonical := normalize(participant_id)
	if canonical.length() != TOTAL_LEN:
		return participant_id
	return "%s-%s" % [canonical.substr(0, DISPLAY_SPLIT),
			canonical.substr(DISPLAY_SPLIT)]


## This machine's letter, derived once and then cached.
##
## Derived from the device rather than drawn at random so it survives a
## reinstall: a machine that started issuing from a second letter would look
## like a second machine in the data, which is the one thing this character is
## for. The cached file wins if it exists, so a letter can also be set by hand
## to force a particular machine to a particular letter.
static func machine_letter() -> String:
	var cached := _read_machine_letter()
	if not cached.is_empty():
		return cached
	var uid := OS.get_unique_id()
	if uid.is_empty():
		# Not implemented on every platform. A per-install value is still
		# better than a constant, and it is cached below either way.
		uid = "%d-%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	var letter := LETTERS[posmod(hash(uid), LETTERS.length())]
	var file := FileAccess.open(MACHINE_LETTER_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(letter)
		file.close()
	return letter


## Pins this machine's letter, replacing the derived one. Returns false and
## changes nothing if the letter is not one the scheme uses.
##
## Worth setting by hand on every computer that issues IDs. Derived letters are
## a hash of the device with nothing coordinating them, so two machines have a
## one in twenty-two chance of sharing one, and a shared letter is the only way
## two machines can ever issue the same ID. Different letters make that
## impossible by construction rather than merely unlikely, which no amount of
## extra randomness can do.
##
## IDs already issued keep the letter they were made with. Changing this only
## affects the next one.
static func set_machine_letter(letter: String) -> bool:
	var clean := letter.strip_edges().to_upper()
	if clean.length() != 1 or not LETTERS.contains(clean):
		return false
	var file := FileAccess.open(MACHINE_LETTER_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("ParticipantId: could not write %s" % MACHINE_LETTER_PATH)
		return false
	file.store_string(clean)
	file.close()
	return true


static func _read_machine_letter() -> String:
	if not FileAccess.file_exists(MACHINE_LETTER_PATH):
		return ""
	var file := FileAccess.open(MACHINE_LETTER_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text().strip_edges().to_upper()
	file.close()
	return text if text.length() == 1 and LETTERS.contains(text) else ""


## Positionally weighted sum over the body, modulo 37.
##
## The weight is what earns the character. An unweighted sum catches a
## substitution but not a transposition, since swapping two characters leaves
## the total unchanged; weighting by position changes the sum by the difference
## between the two values, which is never zero for two different characters.
##
## THE MODULUS MUST BE PRIME, and 32 was tried first and measured wrong: with
## weights 1 to 5 against a modulus of 32, the even weights share a factor with
## it, so a character changed by exactly 16 at the second position, or by a
## multiple of 8 at the fourth, leaves the total unmoved. That accepted 8,000 of
## 372,000 single-character substitutions in the probe. No power-of-two modulus
## can do better: catching substitutions needs every weight coprime to it, which
## means all odd, and catching transpositions needs consecutive weights to
## differ by an odd amount, which two odd numbers never do. 37 is the smallest
## prime above the alphabet and both properties hold under it.
##
## Measured under 37: 0 of 372,000 single substitutions and 0 of 19,407 adjacent
## transpositions accepted. The transposition figure includes swapping the last
## body character with the check character, which is not a special case going
## uncovered: that swap leaves the check unmoved only when the two characters
## are equal, and two equal characters swapped is not an error.
##
## Returns "" for the five residues with no character to represent them. Such a
## body is simply never issued (see generate()), and an ID carrying one can
## match nothing, so verification is unaffected.
const CHECK_MODULUS: int = 37

static func _check_char(body: String) -> String:
	var total := 0
	for i in range(body.length()):
		total += (i + 1) * ALPHABET.find(body[i])
	var residue := posmod(total, CHECK_MODULUS)
	return ALPHABET[residue] if residue < ALPHABET.length() else ""


## Everything this machine already knows an ID to have been used for, as a set.
##
## Three sources, because no single one is complete. The roster holds what was
## issued, including cards that never became sessions. The participant store
## holds anyone who has answered the opening survey here, which covers IDs typed
## in by hand rather than generated. The session folder names catch the rest,
## including the group treatment, which skips the survey and so writes no store
## record.
static func _taken_ids() -> Dictionary:
	var taken := {}
	for id in roster_ids():
		taken[id] = true

	var store := DirAccess.open(ParticipantStore.STORE_DIR)
	if store != null:
		for name in store.get_files():
			if name.ends_with(".json"):
				taken[normalize(name.substr(0, name.length() - 5))] = true

	var sessions := DirAccess.open(DataLogger.SESSIONS_ROOT)
	if sessions != null:
		for folder in sessions.get_directories():
			for candidate in _scheme_shaped_runs(folder):
				taken[candidate] = true
	return taken


## Every run in a folder name that verifies as one of our IDs.
##
## Session folders join the treatment, the participants and the time with
## hyphens, and the participants within that with underscores, so a group
## session reads T3-p001_p002_p003-2026-08-17_1918. Both separators therefore
## have to be split on, and an ID is looked for inside the name rather than
## matched against the whole of it.
static func _scheme_shaped_runs(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	for part in text.replace("_", "-").split("-", false):
		if part.length() == TOTAL_LEN and check_passes(part):
			found.append(normalize(part))
	return found


## The IDs recorded in the roster, canonical and in the order issued.
static func roster_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(ROSTER_PATH):
		return out
	var file := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	if file == null:
		return out
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.is_empty() and has_scheme_shape(trimmed):
			out.append(normalize(trimmed))
	return out


static func _now_utc() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
