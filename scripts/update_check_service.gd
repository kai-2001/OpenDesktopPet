class_name UpdateCheckService
extends RefCounted

## Pure rules for asking GitHub whether a newer public release exists.
##
## Privacy contract: the request is a plain GET to one fixed public endpoint
## with no query string, no body, no cookies, and only the two headers GitHub
## requires. Nothing from the user's settings, saves, characters, agents, or
## installed version is sent. GitHub still sees the caller's IP address, which
## the settings page states before the user turns automatic checks on.

const REPOSITORY := "kai-2001/OpenDesktopPet"
const LATEST_RELEASE_URL := "https://api.github.com/repos/kai-2001/OpenDesktopPet/releases/latest"
const RELEASE_PAGE_PREFIX := "https://github.com/kai-2001/OpenDesktopPet/releases/tag/v"
const REQUEST_HEADERS := [
	"Accept: application/vnd.github+json",
	# GitHub rejects requests without a User-Agent. A fixed product name
	# replaces Godot's default, which would reveal the engine version.
	"User-Agent: OpenDesktopPet",
]
const MAX_RESPONSE_BYTES := 512 * 1024
const REQUEST_TIMEOUT_SECONDS := 15.0

const RESULT_AVAILABLE := "available"
const RESULT_UP_TO_DATE := "up_to_date"
const RESULT_RATE_LIMITED := "rate_limited"
const RESULT_FAILED := "failed"


static func current_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Returns [major, minor, patch], or an empty array for anything that is not a
## plain release tag such as "v0.9.6". Pre-release suffixes are rejected.
static func parse_version(text: String) -> PackedInt32Array:
	var pattern := RegEx.new()
	pattern.compile("^v?(\\d{1,4})\\.(\\d{1,4})\\.(\\d{1,4})$")
	var found := pattern.search(text.strip_edges())
	if found == null:
		return PackedInt32Array()
	return PackedInt32Array([
		int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))
	])


static func is_newer(candidate: String, current: String) -> bool:
	var candidate_parts := parse_version(candidate)
	var current_parts := parse_version(current)
	if candidate_parts.is_empty() or current_parts.is_empty():
		return false
	for index in range(3):
		if candidate_parts[index] != current_parts[index]:
			return candidate_parts[index] > current_parts[index]
	return false


## The page opened for the user is always rebuilt from the validated version,
## so a tampered or unexpected response can never redirect them elsewhere.
static func release_page_url(version: String) -> String:
	var parts := parse_version(version)
	if parts.is_empty():
		return ""
	return "%s%d.%d.%d" % [RELEASE_PAGE_PREFIX, parts[0], parts[1], parts[2]]


## Reads only the release tag and its draft/pre-release flags; release notes
## and URLs from the response are ignored.
static func evaluate_response(
	result: int, response_code: int, body: PackedByteArray, current: String
) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"status": RESULT_FAILED, "version": ""}
	if response_code == 403 or response_code == 429:
		return {"status": RESULT_RATE_LIMITED, "version": ""}
	if response_code != 200 or body.size() > MAX_RESPONSE_BYTES:
		return {"status": RESULT_FAILED, "version": ""}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {"status": RESULT_FAILED, "version": ""}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {"status": RESULT_FAILED, "version": ""}
	if bool(parsed.get("draft", false)) or bool(parsed.get("prerelease", false)):
		return {"status": RESULT_UP_TO_DATE, "version": ""}
	var parts := parse_version(String(parsed.get("tag_name", "")))
	if parts.is_empty():
		return {"status": RESULT_FAILED, "version": ""}
	var version := "%d.%d.%d" % [parts[0], parts[1], parts[2]]
	if is_newer(version, current):
		return {"status": RESULT_AVAILABLE, "version": version}
	return {"status": RESULT_UP_TO_DATE, "version": version}
