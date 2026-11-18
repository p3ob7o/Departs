#!/usr/bin/env python3
"""Build a disposable German stress catalog; never add German to the product.

Usage: python3 ios/scripts/test-pseudolocalization.py SIMULATOR_UUID OS OUTPUT_PREFIX DERIVED_DATA
The copied project, logs and result bundle live outside the repo. Reuse the
destination's derived data, with no other build running there at the same time.
"""
import copy
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
device, os_version, output, derived = sys.argv[1:]
prefix = Path(output).resolve()
derived = Path(derived).resolve()
assert not prefix.is_relative_to(ROOT), "Keep test builds outside the repository"
assert not derived.is_relative_to(ROOT), "Keep derived data outside the repository"
project = prefix / "project"
assert not project.exists(), "Choose a fresh output prefix"
shutil.copytree(ROOT / "ios/Departs", project)

# These phrases stress German word lengths and sentence order. The remaining
# strings are bounded, accented English with added length, not a translation.
german = {
    "Couldn't find your location · Try again": "Standort nicht gefunden · Erneut versuchen",
    "In %@": "In %@",
    "Now": "Jetzt",
    "Walking directions": "Wegbeschreibung zu Fuß",
    "%@ walk": "%@ Fußweg",
    "%@ walk from this area": "%@ Fußweg ab diesem Suchgebiet",
    "Nothing soon": "Keine baldige Abfahrt",
    "Nothing leaves here in the next hour": "Hier fährt in der nächsten Stunde nichts ab",
    "Saved times from %@ · Refresh": "Gespeicherte Zeiten von %@ · Aktualisieren",
}
accents = str.maketrans("aeiouAEIOU", "áëïöüÁËÏÖÜ")
placeholder = re.compile(r"(%(?:\d+\$)?(?:lld|ld|d|@)|\$\{[^}]+\})")

def pseudo(value):
    if value in german:
        return "［" + german[value] + "］"
    parts = placeholder.split(value)
    text = "".join(part if placeholder.fullmatch(part) else part.translate(accents) for part in parts)
    padding = " zusätzliche Zeichen" if len(value) > 8 else " länger"
    return "［" + text + padding + "］"

def transform(node):
    if isinstance(node, dict):
        if "stringUnit" in node:
            node["stringUnit"]["value"] = pseudo(node["stringUnit"]["value"])
            node["stringUnit"]["state"] = "translated"
        else:
            for value in node.values():
                transform(value)

for name in ("Localizable", "InfoPlist"):
    path = project / "Departs" / f"{name}.xcstrings"
    catalog = json.loads(path.read_text())
    for key, entry in catalog["strings"].items():
        source = entry.get("localizations", {}).get("en", {"stringUnit": {"value": key}})
        localized = copy.deepcopy(source)
        if entry.get("shouldTranslate") is not False:
            transform(localized)
        entry.setdefault("localizations", {})["de"] = localized
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")

command = [
    "xcodebuild", "-project", str(project / "Departs.xcodeproj"), "-scheme", "Departs",
    "-destination", f"platform=iOS Simulator,id={device},OS={os_version}",
    "-derivedDataPath", str(derived),
    "-resultBundlePath", str(prefix.with_suffix(".xcresult")),
    "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
    "-only-testing:DepartsUITests/DepartsUITests/testGermanRegionWithExpandedPseudoLocalization",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG PSEUDO_LOCALIZATION", "test",
]
with prefix.with_suffix(".log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
print(f"Pseudolocalization result: {result.returncode}; log: {prefix.with_suffix('.log')}")
sys.exit(result.returncode)
