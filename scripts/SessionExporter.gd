class_name SessionExporter
## SessionExporter.gd
## Packs every session folder into one zip and puts it somewhere the researcher
## can actually reach.
##
## On a desktop machine the data is already reachable: the menu opens the folder
## and you copy it. On Android it is not. `user://` maps to the app's private
## storage, which is not browsable over USB and not visible to a file manager,
## so a tablet that has run a day of sessions has no way to hand them over. That
## is what this is for, and the desktop build gets it too, since one zip per
## machine is easier to collect than a folder of folders either way.
##
## Nothing here reads or interprets the data. It copies bytes.

## Where the zip is written, in order of preference. The first writable one
## wins, and the caller is told which it was, because on Android the answer
## decides whether the file can be retrieved by plugging in a cable or only by
## sharing it from the device.
##
## Downloads first: it is the one folder every Android file manager opens on,
## and on desktop it is where a browser would have put it. `user://exports` is
## the fallback that always works, and on Android it is also the one nobody can
## get at, so it is last and the caller says so.
const EXPORT_SUBDIR: String = "user://exports/"


## Writes a zip of every session folder. Returns a report for the UI:
##
##   ok            bool    whether a file was written
##   path          String  absolute path of the zip
##   sessions      int     how many session folders went in
##   files         int     how many files in total
##   bytes         int     size of the zip on disk
##   reachable     bool    false when it landed somewhere only the app can see
##   error         String  set when ok is false
static func export_all() -> Dictionary:
	var root: String = DataLogger.SESSIONS_ROOT
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return {"ok": false, "error": "No session folder yet at %s."
				% ProjectSettings.globalize_path(root)}

	var sessions: PackedStringArray = dir.get_directories()
	sessions.sort()
	if sessions.is_empty():
		return {"ok": false, "error": "There are no sessions to export."}

	var destination: Dictionary = _destination()
	var zip_path: String = destination["dir"].path_join(_zip_name())
	var packer: ZIPPacker = ZIPPacker.new()
	var err: int = packer.open(zip_path)
	if err != OK:
		return {"ok": false, "error": "Could not create %s (%s)."
				% [zip_path, error_string(err)]}

	var file_count: int = 0
	for session: String in sessions:
		file_count += _add_folder(packer, root.path_join(session), session)
	packer.close()

	var written: FileAccess = FileAccess.open(zip_path, FileAccess.READ)
	var size: int = 0
	if written != null:
		size = written.get_length()
		written.close()

	return {
		"ok": size > 0,
		"path": ProjectSettings.globalize_path(zip_path),
		"sessions": sessions.size(),
		"files": file_count,
		"bytes": size,
		"reachable": bool(destination["reachable"]),
		"error": "" if size > 0 else "The zip was created but is empty.",
	}


## Adds one session folder to the archive, keeping the folder name as the path
## inside the zip so unpacking reproduces the layout the analysis tools expect.
static func _add_folder(packer: ZIPPacker, folder: String, prefix: String) -> int:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return 0
	var added: int = 0
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for name: String in names:
		var file: FileAccess = FileAccess.open(folder.path_join(name), FileAccess.READ)
		if file == null:
			continue
		var bytes: PackedByteArray = file.get_buffer(file.get_length())
		file.close()
		if packer.start_file(prefix.path_join(name)) != OK:
			continue
		packer.write_file(bytes)
		packer.close_file()
		added += 1
	return added


## The first writable candidate, tested by writing rather than by assuming.
##
## `reachable` is the honest part: on Android the fallback is inside the app's
## private storage, where the file exists but nobody can collect it without the
## share sheet, and the researcher needs telling that rather than being handed a
## path that looks fine.
static func _destination() -> Dictionary:
	for system_dir: int in [OS.SYSTEM_DIR_DOWNLOADS, OS.SYSTEM_DIR_DOCUMENTS]:
		var candidate: String = OS.get_system_dir(system_dir)
		if not candidate.is_empty() and _is_writable(candidate):
			return {"dir": candidate, "reachable": true}
	DirAccess.make_dir_recursive_absolute(EXPORT_SUBDIR)
	# Reachable on desktop, where user:// is an ordinary folder the menu can
	# open. Not on Android, which is the platform this exists for.
	return {"dir": EXPORT_SUBDIR, "reachable": not OS.has_feature("android")}


## Writability decided by writing a file and removing it. `DirAccess.open()`
## succeeding proves only that the folder can be listed, and on Android a public
## folder can list and still refuse writes.
static func _is_writable(path: String) -> bool:
	var probe: String = path.path_join(".cyclecity_write_test")
	var file: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.store_8(0)
	file.close()
	DirAccess.remove_absolute(probe)
	return true


## Named for the machine and the moment, since collecting several tablets into
## one place is the whole point and "sessions.zip" three times over is not
## something anyone should have to untangle.
static func _zip_name() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system()
	var host: String = OS.get_model_name().strip_edges().replace(" ", "-")
	if host.is_empty():
		host = "device"
	return "cyclecity-%s-%04d-%02d-%02d_%02d%02d.zip" % [host,
			now["year"], now["month"], now["day"], now["hour"], now["minute"]]
