class_name TaskReminderDateTime
extends RefCounted

# Dates are "YYYY-MM-DD" and times "HH:MM" in local time. Parsing is lenient
# because Chinese input methods type full-width digits and separators.

const FULL_WIDTH_DIGITS := "０１２３４５６７８９"


static func parse_time(text: String) -> String:
	var value := _to_half_width(text).replace(" ", "").replace(".", ":")
	var hour := -1
	var minute := 0
	if value.contains(":"):
		var parts := value.split(":")
		if parts.size() != 2 or not _is_digits(parts[0], 1, 2) or not _is_digits(parts[1], 1, 2):
			return ""
		hour = int(parts[0])
		minute = int(parts[1])
	elif _is_digits(value, 1, 2):
		hour = int(value)
	elif _is_digits(value, 3, 4):
		hour = int(value.left(value.length() - 2))
		minute = int(value.right(2))
	else:
		return ""
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return ""
	return "%02d:%02d" % [hour, minute]


# A month and day without a year use the year of `today`.
static func parse_date(text: String, today: String) -> String:
	var value := _to_half_width(text).replace(" ", "")
	for separator: String in ["/", ".", "年", "月"]:
		value = value.replace(separator, "-")
	value = value.trim_suffix("日").trim_suffix("-")
	var parts: PackedStringArray
	if value.contains("-"):
		parts = value.split("-")
	elif _is_digits(value, 8, 8):
		parts = [value.left(4), value.substr(4, 2), value.right(2)]
	elif _is_digits(value, 3, 4):
		parts = [value.left(value.length() - 2), value.right(2)]
	else:
		return ""
	if parts.size() == 2:
		parts.insert(0, today.left(4))
	if parts.size() != 3 or not _is_digits(parts[0], 4, 4) \
			or not _is_digits(parts[1], 1, 2) or not _is_digits(parts[2], 1, 2):
		return ""
	var year := int(parts[0])
	var month := int(parts[1])
	var day := int(parts[2])
	if month < 1 or month > 12 or day < 1 or day > days_in_month(year, month):
		return ""
	return format_date(year, month, day)


# Section 0 is the hour and 1 the minute; each wraps on its own.
static func step_time(time: String, section: int, delta: int) -> String:
	var hour := int(time.left(2))
	var minute := int(time.right(2))
	if section == 0:
		hour = posmod(hour + delta, 24)
	else:
		minute = posmod(minute + delta, 60)
	return "%02d:%02d" % [hour, minute]


# Section 0 is the year, 1 the month and 2 the day. Days move through the
# calendar; months and years keep the day inside the new month.
static func step_date(date: String, section: int, delta: int) -> String:
	if section == 2:
		return add_days(date, delta)
	var year := int(date.left(4))
	var month := int(date.substr(5, 2))
	var day := int(date.right(2))
	if section == 0:
		year += delta
	else:
		var months := year * 12 + month - 1 + delta
		year = floori(months / 12.0)
		month = posmod(months, 12) + 1
	return format_date(year, month, mini(day, days_in_month(year, month)))


static func add_days(date: String, days: int) -> String:
	var timestamp := Time.get_unix_time_from_datetime_string(date) + days * 86400
	return Time.get_date_string_from_unix_time(timestamp)


static func weekday(date: String) -> int:
	var timestamp := Time.get_unix_time_from_datetime_string(date)
	return int(Time.get_datetime_dict_from_unix_time(timestamp).get("weekday", 0))


static func days_in_month(year: int, month: int) -> int:
	if month == 2:
		return 29 if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0) else 28
	if month in [4, 6, 9, 11]:
		return 30
	return 31


static func format_date(year: int, month: int, day: int) -> String:
	return "%04d-%02d-%02d" % [year, month, day]


static func _to_half_width(text: String) -> String:
	var value := text.strip_edges().replace("：", ":").replace("／", "/") \
		.replace("－", "-").replace("．", ".").replace("　", " ")
	for digit: int in 10:
		value = value.replace(FULL_WIDTH_DIGITS[digit], str(digit))
	return value


static func _is_digits(text: String, min_length: int, max_length: int) -> bool:
	if text.length() < min_length or text.length() > max_length:
		return false
	for index: int in text.length():
		if text.unicode_at(index) < 48 or text.unicode_at(index) > 57:
			return false
	return true
