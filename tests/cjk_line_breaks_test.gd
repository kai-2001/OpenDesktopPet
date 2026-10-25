extends SceneTree

const CjkLineBreaksScript = preload("res://scripts/cjk_line_breaks.gd")
const B := CjkLineBreaksScript.BREAK

var _failures := 0


func _init() -> void:
	var insert := func(text: String) -> String:
		return CjkLineBreaksScript.insert_break_opportunities(text)

	_assert_equal(
		insert.call("願望完成！心情"),
		"願" + B + "望" + B + "完" + B + "成！" + B + "心" + B + "情",
		"ideographs get break opportunities, but not before closing punctuation"
	)
	_assert_equal(
		insert.call("親密度和 XP 也增加了。"),
		"親" + B + "密" + B + "度" + B + "和 XP 也" + B + "增" + B + "加" + B + "了。",
		"Latin words and spaces are left alone"
	)
	_assert_equal(
		insert.call("Lv.3解鎖"),
		"Lv.3" + B + "解" + B + "鎖",
		"a break is allowed between Latin text and an ideograph"
	)
	_assert_equal(
		insert.call("（剩餘約 5 分鐘）"),
		"（剩" + B + "餘" + B + "約 5 分" + B + "鐘）",
		"opening punctuation stays with the next character and closing with the previous"
	)
	_assert_equal(insert.call("hello world"), "hello world", "plain English is unchanged")
	_assert_equal(insert.call("🥕"), "🥕", "a lone emoji is unchanged")
	_assert_equal(
		insert.call("好吃！\n願望"),
		"好" + B + "吃！\n願" + B + "望",
		"no break is inserted around a newline"
	)
	for sample: String in ["願望完成！心情大幅提升", "Luna 來了！右鍵操作・雙擊摸摸", "💤", ""]:
		var once: String = insert.call(sample)
		_assert_equal(CjkLineBreaksScript.strip(once), sample, "strip restores: %s" % sample)
		_assert_equal(insert.call(once), once, "inserting twice changes nothing: %s" % sample)

	if _failures > 0:
		push_error("CJK_LINE_BREAKS_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
		return
	print("CJK_LINE_BREAKS_TEST_OK")
	quit(0)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures += 1
	push_error("Assertion failed: %s (actual=%s expected=%s)" % [
		label, String(actual).replace(B, "|"), String(expected).replace(B, "|")
	])
