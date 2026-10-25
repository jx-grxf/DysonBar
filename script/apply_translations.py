"""Writes the German strings from translations_de.json into the String Catalog.
Keys without a translation that are pure symbols or placeholders are marked
as not translatable."""
import json, pathlib, sys

root = pathlib.Path(__file__).resolve().parent.parent
catalog_path = root / "Sources/DysonBar/Resources/Localizable.xcstrings"
catalog = json.loads(catalog_path.read_text())
german = json.loads((root / "script/translations_de.json").read_text())

missing = []
for key, entry in catalog["strings"].items():
    if key in german:
        entry.setdefault("localizations", {})["de"] = {
            "stringUnit": {"state": "translated", "value": german[key]}
        }
        entry.pop("shouldTranslate", None)
    elif not any(c.isalpha() for c in key.replace("%@", "").replace("%lld", "")) or key in {"DysonBar", "DysonBar %@", "name@example.com"}:
        entry["shouldTranslate"] = False
    else:
        missing.append(key)

catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
if missing:
    print("untranslated:", *missing, sep="\n  ")
    sys.exit(1)
