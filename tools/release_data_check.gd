extends SceneTree
## Validates the data a Web release ships (P22, plan M6-M9 decision 8): every record under
## res://data except res://data/test/ (the Web preset leaves the test-only records out), with the
## same validator the game runs at start-up (DataValidator), so a shipped record that refers to a
## test-only record - which would stop the released game at its data error screen - is caught at
## build time. Prints one line "RELEASE_DATA_CHECK {json}" ({"records", "errors": [...]}) and exits
## with 1 when there is an error.
##
##   tools/gd.sh --headless --path . -s res://tools/release_data_check.gd
## tools/build_web.sh runs it for the Web preset.

const DATA_ROOT := "res://data"
const TEST_DIR := "res://data/test/"


func _init() -> void:
	var records := {}
	var refs: Array = []
	var errors := PackedStringArray()
	for path in JsonIO.list_json_files(DATA_ROOT):
		if path.begins_with(TEST_DIR):
			continue
		var parsed := JsonIO.read_file(path)
		if not parsed.ok:
			errors.append(str(parsed.error))
			continue
		var result := DataValidator.validate_record(parsed.data, path)
		errors.append_array(result.errors)
		refs.append_array(result.refs)
		if typeof(parsed.data) == TYPE_DICTIONARY and typeof(parsed.data.get("id")) == TYPE_STRING:
			records[parsed.data.id] = parsed.data
	errors.append_array(DataValidator.validate_references(records, refs))
	print("RELEASE_DATA_CHECK " + JSON.stringify({"records": records.size(), "errors": Array(errors)}))
	quit(1 if not errors.is_empty() else 0)
