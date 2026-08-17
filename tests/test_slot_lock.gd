extends Node
## Two copies of the game must not open the same save: each keeps its own
## Player in memory and each save overwrites the other's, losing cards and
## coins silently. A slot is claimed with a heartbeat file - a plain "file
## exists" flag would lock a player out of their own save after a crash.
## Run: godot --headless --quit-after 200 res://tests/test_slot_lock.tscn

## Well outside SaveSystem.SLOT_COUNT, so a real save is never touched.
const SLOT := 96

func _lock_path() -> String:
	return "user://slot%d/slot.lock" % SLOT

func _write_lock(pid: int, age_seconds: float) -> void:
	DirAccess.make_dir_recursive_absolute("user://slot%d" % SLOT)
	var f := FileAccess.open(_lock_path(), FileAccess.WRITE)
	f.store_var({"pid": pid, "at": Time.get_unix_time_from_system() - age_seconds})
	f = null

func _ready() -> void:
	SaveSystem.release_lock(SLOT)
	assert(not SaveSystem.is_locked(SLOT), "a slot with no lock file reads as locked")

	# Taking a free slot works, and taking it again from this same process
	# still works - a copy must never lock itself out of the save it holds.
	assert(SaveSystem.acquire_lock(SLOT), "could not claim a free slot")
	assert(not SaveSystem.is_locked(SLOT), "our own lock counts as somebody else's")
	assert(SaveSystem.acquire_lock(SLOT), "re-claiming our own slot failed")

	# Another process holding it, heartbeat fresh: refused.
	_write_lock(OS.get_process_id() + 1, 0.0)
	assert(SaveSystem.is_locked(SLOT), "a live lock from another process was ignored")
	assert(not SaveSystem.acquire_lock(SLOT), "a slot held by another copy was handed over anyway")

	# Same lock, heartbeat gone quiet: the holder is presumed dead, so the
	# save is reachable again. This is the case a crash leaves behind.
	_write_lock(OS.get_process_id() + 1, SaveSystem.LOCK_STALE_SECONDS + 5.0)
	assert(not SaveSystem.is_locked(SLOT), "a stale lock still blocks the save - a crash would strand the player")
	assert(SaveSystem.acquire_lock(SLOT), "could not take over a stale lock")

	# Just inside the timeout it must still count, or a brief hitch in the
	# holder would hand its save to the other copy mid-play.
	_write_lock(OS.get_process_id() + 1, SaveSystem.LOCK_STALE_SECONDS - 5.0)
	assert(SaveSystem.is_locked(SLOT), "a lock just short of the timeout was treated as stale")

	# Releasing frees it.
	_write_lock(OS.get_process_id(), 0.0)
	SaveSystem.release_lock(SLOT)
	assert(not FileAccess.file_exists(_lock_path()), "the lock file survived release")

	# The heartbeat has to be well inside the timeout, or a lock expires
	# while its holder is still playing.
	assert(Game.LOCK_HEARTBEAT_SECONDS * 3.0 <= SaveSystem.LOCK_STALE_SECONDS,
		"heartbeat %.0fs is too close to the %.0fs timeout" % [Game.LOCK_HEARTBEAT_SECONDS, SaveSystem.LOCK_STALE_SECONDS])

	DirAccess.remove_absolute("user://slot%d" % SLOT)
	print("OK - slot locking blocks a second copy and expires on its own")
	get_tree().quit()
