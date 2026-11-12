import json
from pathlib import Path
import re
import subprocess

tables = {}
for path in sorted(Path("Resources").glob("*.lproj/Localizable.strings")):
    tables[path.parent.stem] = json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", str(path)]))
baseline = tables["en"]
for language, table in tables.items():
    assert table.keys() == baseline.keys(), f"Missing or extra keys in {language}"
    for key, value in table.items():
        assert value, f"Empty translation: {language}/{key}"
        assert re.findall(r"%(?:\d+\$)?[@df]", value) == re.findall(r"%(?:\d+\$)?[@df]", baseline[key]), key
for source in Path("Sources").glob("*.swift"):
    for key in re.findall(r'L.text\("([a-zA-Z.]+)"', source.read_text()):
        assert key in baseline, f"Unknown translation key: {source}/{key}"
print(f"PASS: {len(baseline)} keys, matching placeholders, {len(tables)} complete languages")
