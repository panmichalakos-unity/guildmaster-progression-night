class_name SeedLoader
extends RefCounted

## Seed loader (M0-005). Pure — no scene-tree dependencies.
##
## Convention (docs/decisions.md ADR-0007, data/seeds/README.md):
##   * data/seeds/manifest.json lists seed files in dependency order.
##   * One CSV file = one table; the header row names the columns.
##   * Seed files NEVER carry integer ids — slugs are the natural keys.
##     FK columns are authored as `<something>_slug` and resolved via the
##     manifest's `refs` declarations (slug -> integer id lookup).
##   * Upsert semantics: ON CONFLICT(key) DO UPDATE for non-key columns
##     (preserves integer PKs so existing FK references stay stable);
##     DO NOTHING when there are no non-key columns (pure bridges).
##   * The whole load runs in ONE transaction: all seeds or none.
##   * Values are coerced from CSV text using PRAGMA table_info types;
##     empty cells become NULL.

const DEFAULT_SEEDS_DIR := "res://data/seeds"
const MANIFEST_NAME := "manifest.json"


## Loads all seeds listed in `<seeds_dir>/manifest.json` into `db`.
## Returns: { ok: bool, files: Array[Dictionary{file, table, rows}],
##            failed_file: String, error: String }
static func load_seeds(db: Variant, seeds_dir: String = DEFAULT_SEEDS_DIR) -> Dictionary:
	var result := {"ok": true, "files": [], "failed_file": "", "error": ""}
	var manifest_path := seeds_dir.path_join(MANIFEST_NAME)
	var manifest_text := _read_file(manifest_path)
	if manifest_text.is_empty():
		return _fail(result, MANIFEST_NAME, "cannot read manifest at %s" % manifest_path)
	var manifest: Variant = JSON.parse_string(manifest_text)
	if manifest == null or not (manifest is Dictionary) or not manifest.has("files"):
		return _fail(result, MANIFEST_NAME, "manifest is not valid JSON with a 'files' array")

	db.query("BEGIN TRANSACTION;")
	for entry: Dictionary in manifest["files"]:
		var filename := str(entry.get("file", ""))
		var table := str(entry.get("table", ""))
		if filename.is_empty() or table.is_empty():
			db.query("ROLLBACK;")
			return _fail(result, filename, "manifest entry missing 'file' or 'table'")
		var loaded := _load_file(db, seeds_dir.path_join(filename), table, entry)
		if not loaded.ok:
			db.query("ROLLBACK;")
			return _fail(result, filename, loaded.error)
		result.files.append({"file": filename, "table": table, "rows": loaded.rows})
	db.query("COMMIT;")
	return result


static func _fail(result: Dictionary, filename: String, error: String) -> Dictionary:
	result.ok = false
	result.failed_file = filename
	result.error = error
	push_error("SeedLoader: seed '%s' failed: %s" % [filename, error])
	return result


## Loads one CSV file into `table`. Returns {ok, rows, error}.
static func _load_file(db: Variant, path: String, table: String, entry: Dictionary) -> Dictionary:
	var rows := _read_csv(path)
	if rows.is_empty():
		return {"ok": false, "rows": 0, "error": "cannot read CSV (or file is empty) at %s" % path}
	var header: PackedStringArray = rows[0]
	var column_types := _table_column_types(db, table)
	if column_types.is_empty():
		return {"ok": false, "rows": 0, "error": "table '%s' does not exist in the DB" % table}

	# Resolve manifest ref declarations: seed column (slug) -> DB column (id).
	var refs: Array = entry.get("refs", [])
	var ref_by_column := {}  # seed column name -> {as, lookup: {slug: id}}
	for ref: Dictionary in refs:
		var lookup: Variant = _slug_lookup(db, str(ref["table"]))
		if lookup == null:
			return {
				"ok": false,
				"rows": 0,
				"error": "ref table '%s' is missing or has no slug column" % ref["table"]
			}
		# an EMPTY lookup is fine — unknown slugs fail per-row with a precise message
		ref_by_column[str(ref["column"])] = {"as": str(ref["as"]), "lookup": lookup}

	# Map seed header -> DB columns, validating against the real table schema.
	var db_columns: Array[String] = []
	for seed_column in header:
		var db_column := (
			str(ref_by_column[seed_column]["as"])
			if ref_by_column.has(seed_column)
			else String(seed_column)
		)
		if not column_types.has(db_column):
			return {
				"ok": false,
				"rows": 0,
				"error":
				(
					"column '%s' (from CSV header '%s') not in table '%s'"
					% [db_column, seed_column, table]
				)
			}
		db_columns.append(db_column)

	# Key columns: 'slug' when present, else the manifest 'key' array (bridges).
	var key_columns: Array[String] = []
	if "slug" in db_columns:
		key_columns = ["slug"]
	else:
		for key in entry.get("key", []):
			key_columns.append(str(key))
	if key_columns.is_empty():
		return {
			"ok": false,
			"rows": 0,
			"error":
			"no upsert key: table '%s' has no slug column and manifest declares no 'key'" % table
		}

	var sql := _build_upsert(table, db_columns, key_columns)
	var row_count := 0
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		if row.size() == 1 and String(row[0]).strip_edges().is_empty():
			continue  # trailing blank line
		if row.size() != header.size():
			return {
				"ok": false,
				"rows": row_count,
				"error": "row %d has %d fields, header has %d" % [i + 1, row.size(), header.size()]
			}
		var values := []
		for j in header.size():
			var coerced := _coerce(
				db, String(row[j]), String(header[j]), db_columns[j], column_types, ref_by_column
			)
			if not coerced.ok:
				return {
					"ok": false, "rows": row_count, "error": "row %d: %s" % [i + 1, coerced.error]
				}
			values.append(coerced.value)
		if not db.query_with_bindings(sql, values):
			return {
				"ok": false, "rows": row_count, "error": "row %d: %s" % [i + 1, db.error_message]
			}
		row_count += 1
	return {"ok": true, "rows": row_count, "error": ""}


static func _build_upsert(
	table: String, db_columns: Array[String], key_columns: Array[String]
) -> String:
	var placeholders := []
	for _c in db_columns:
		placeholders.append("?")
	var non_key: Array[String] = []
	for column in db_columns:
		if column not in key_columns:
			non_key.append(column)
	var conflict := ", ".join(key_columns)
	var sql := (
		"INSERT INTO %s (%s) VALUES (%s) ON CONFLICT(%s) "
		% [table, ", ".join(db_columns), ", ".join(placeholders), conflict]
	)
	if non_key.is_empty():
		return sql + "DO NOTHING;"
	var sets: Array[String] = []
	for column in non_key:
		sets.append("%s = excluded.%s" % [column, column])
	return sql + "DO UPDATE SET %s;" % ", ".join(sets)


## Coerces one CSV cell. Returns {ok, value, error}.
static func _coerce(
	_db: Variant,
	raw: String,
	seed_column: String,
	db_column: String,
	column_types: Dictionary,
	ref_by_column: Dictionary
) -> Dictionary:
	if raw.strip_edges().is_empty():
		return {"ok": true, "value": null, "error": ""}
	if ref_by_column.has(seed_column):
		var lookup: Dictionary = ref_by_column[seed_column]["lookup"]
		if not lookup.has(raw):
			return {
				"ok": false,
				"value": null,
				"error": "unknown slug '%s' for ref column '%s'" % [raw, seed_column]
			}
		return {"ok": true, "value": lookup[raw], "error": ""}
	var declared := str(column_types.get(db_column, "TEXT")).to_upper()
	if declared.contains("INT"):
		if not raw.strip_edges().is_valid_int():
			return {
				"ok": false,
				"value": null,
				"error": "column '%s' expects INTEGER, got '%s'" % [db_column, raw]
			}
		return {"ok": true, "value": raw.strip_edges().to_int(), "error": ""}
	if declared.contains("REAL") or declared.contains("FLOA") or declared.contains("DOUB"):
		if not raw.strip_edges().is_valid_float():
			return {
				"ok": false,
				"value": null,
				"error": "column '%s' expects REAL, got '%s'" % [db_column, raw]
			}
		return {"ok": true, "value": raw.strip_edges().to_float(), "error": ""}
	return {"ok": true, "value": raw, "error": ""}


## {column_name: declared_type} for `table`, empty if the table is missing.
static func _table_column_types(db: Variant, table: String) -> Dictionary:
	var types := {}
	db.query_with_bindings("SELECT name, type FROM pragma_table_info(?);", [table])
	for row in db.query_result:
		types[str(row["name"])] = str(row["type"])
	return types


## {slug: <pk id>} for a slug-keyed table, possibly empty.
## Returns null (structural error) when the table is missing, has no primary
## key, or has no slug column — distinct from "exists but has no rows yet".
static func _slug_lookup(db: Variant, table: String) -> Variant:
	db.query_with_bindings("SELECT name FROM pragma_table_info(?) WHERE pk = 1;", [table])
	if db.query_result.is_empty():
		return null
	var pk := str(db.query_result[0]["name"])
	db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM pragma_table_info(?) WHERE name = 'slug';", [table]
	)
	if int(db.query_result[0]["n"]) == 0:
		return null
	var lookup := {}
	db.query("SELECT slug, %s AS pk_value FROM %s;" % [pk, table])
	for row in db.query_result:
		lookup[str(row["slug"])] = row["pk_value"]
	return lookup


static func _read_csv(path: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return rows
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and String(row[0]).is_empty() and file.eof_reached():
			break  # final newline artifact
		rows.append(row)
	return rows


static func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
