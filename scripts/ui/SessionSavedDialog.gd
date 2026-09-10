class_name SessionSavedDialog
extends AcceptDialog
## SessionSavedDialog.gd
## Confirms to the RESEARCHER that a finished session reached disk, and says
## what it wrote, before the screen returns to the menu.
##
## Nothing told anyone the data had been saved. The files land in a folder the
## operating system hides, so confirming a session meant leaving the game,
## finding %APPDATA% and counting files by hand — which nobody does between
## participants, so in practice a session was assumed saved and only found
## missing later, when the participant is long gone and the session cannot be
## repeated.
##
## Deliberately blocking. One click is the right price for "the data is
## definitely there", and pausing here also means the confirmation is seen in a
## chained sitting, where the screen would otherwise go straight into the second
## treatment.
##
## Not participant-facing. It appears after the closing survey, once the person
## has finished and the researcher is the one at the screen.

## Files a finished session must contain. Their absence is the failure this
## dialog exists to catch, so it is stated rather than left to be noticed in the
## file list.
const REQUIRED_FILES: PackedStringArray = ["events.json", "rounds.csv", "summary.json"]


func _ready() -> void:
	title = "Session saved"
	ok_button_text = "Continue"
	exclusive = true
	# The dialog outlives a paused tree and any dimming overlay left on screen.
	process_mode = Node.PROCESS_MODE_ALWAYS


## `report` comes from DataLogger.session_report(), which reads the finished
## folder back rather than reporting what it meant to write.
func show_for(report: Dictionary) -> void:
	dialog_text = _compose(report)
	popup_centered()


func _compose(report: Dictionary) -> String:
	var files: Array = report.get("files", [])
	var names := PackedStringArray()
	for f: Dictionary in files:
		names.append(str(f.get("name", "")))

	var lines := PackedStringArray()
	lines.append(str(report.get("session_id", "")))
	lines.append(str(report.get("path", "")))
	lines.append("")
	# Stated in the form a card should be written in, since this is the last
	# moment the participant is still in the room and the ID has to travel with
	# them to the group session on another machine.
	var who := _participant_line(report)
	if not who.is_empty():
		lines.append(who)
		lines.append("")

	var missing := PackedStringArray()
	for required: String in REQUIRED_FILES:
		if not names.has(required):
			missing.append(required)

	if files.is_empty():
		lines.append("NOTHING WAS WRITTEN. Do not start the next session; the")
		lines.append("data for this one is not on disk.")
		return "\n".join(lines)

	lines.append("%d file%s, %s" % [files.size(), "" if files.size() == 1 else "s",
			_format_size(int(report.get("total_bytes", 0)))])
	if not missing.is_empty():
		lines.append("")
		lines.append("MISSING: %s" % ", ".join(missing))
		lines.append("The session may not have finished. Check before continuing.")
	lines.append("")

	for f: Dictionary in files:
		lines.append("    %-22s %s" % [str(f.get("name", "")),
				_format_size(int(f.get("bytes", 0)))])

	lines.append("")
	lines.append("Copy this whole folder to collect the data. codebook.csv inside")
	lines.append("it describes every file and every column.")
	return "\n".join(lines)


## Who the session was recorded against, spaced out for reading aloud and for
## copying onto a card. Issued IDs are shown hyphenated the way they were on the
## menu; anything typed by hand is shown exactly as it was entered.
func _participant_line(report: Dictionary) -> String:
	var shown := PackedStringArray()
	for id in report.get("participant_ids", []):
		var text := str(id).strip_edges()
		if text.is_empty():
			continue
		shown.append(ParticipantId.format_for_display(text)
				if ParticipantId.looks_generated(text) else text)
	if shown.is_empty():
		return ""
	return "Participant %s: %s" % ["ID" if shown.size() == 1 else "IDs", ", ".join(shown)]


## Sizes in whole units. A researcher checking that a session saved needs to see
## that a file is not empty, not its exact byte count.
static func _format_size(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%d KB" % int(round(bytes / 1024.0))
	return "%d bytes" % bytes
