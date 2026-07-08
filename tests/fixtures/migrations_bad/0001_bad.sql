-- Test fixture: deliberately broken migration (used by migrator_test.gd to
-- prove failures name the offending file and roll back cleanly).
CREATE TABLE ok_table (id INTEGER PRIMARY KEY);
THIS IS NOT VALID SQL;
