# Showcase validation — 10 October 2026

Executed locally with Godot 4.7 stable, Python 3.12 and gdtoolkit 4.5.0:

| Check | Result |
| --- | --- |
| Project import and headless boot | Passed |
| GdUnit4 suite | 241 tests passed, zero failures |
| GDScript format and lint checks | Passed |
| Python seed integrity | 291 checks, zero errors; one existing warning |
| Migration smoke | Passed with the six-migration, 52-table contract |
| Seed-loader smoke | Passed after correcting initial-content counts |
| Roster, vertical-slice and first-night smokes | Passed |
| Encounter balance contracts | Passed with 150 pulls |
| Preparation-leverage probes | Passed with 150 pulls |

The seed-check warning flags six specializations without utility and asks for an intentional-design review. It is not suppressed by this update.

These checks establish reproducibility of the tested prototype paths, not a finished game, complete release validation or a visual assessment of the UI. CI status remains independently visible in the actual GitHub Actions run.
