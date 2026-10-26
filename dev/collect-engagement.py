"""Archive native headless evidence; UI traces are not GPU screenshots."""
import argparse
import hashlib
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("evidence", type=Path)
parser.add_argument("--out", required=True, type=Path)
args = parser.parse_args()
result = json.loads((args.evidence / "result.json").read_text(encoding="utf-8-sig"))
report = result["report"]
assert result["ok"] and report["result"] == "PASS", "native report did not pass"
assert report["summary"]["total_errors"] == 0, "native report contains errors"
invocation = json.loads((args.evidence / "invocation.json").read_text(encoding="utf-8-sig"))
assert "-graphicsheadless" in invocation["args"], "expected a windowless invocation"
assert "-nosound" in invocation["args"], "expected a silent invocation"
markers, runs, fusion, recipes, layouts = [], [], [], [], {}
for line in (args.evidence / "runtime.log").read_text(encoding="utf-8-sig").splitlines():
    record = json.loads(line)
    text = record.get("text", "")
    if not text.startswith("[lua]"):
        continue  # The runtime repeats each Lua line in a separate native record.
    match = re.search(r"\[(EngagementRun|EngagementFusion|RecipeScenario|UILayoutBatch)\]\s+(\{.*\})", text)
    if match:
        tag, data = match[1], json.loads(match[2])
        if tag == "EngagementRun":
            runs.append(data)
        elif tag == "EngagementFusion":
            fusion.append(data)
        elif tag == "RecipeScenario":
            recipes.append(data)
        else:
            layout = layouts.setdefault(data["name"], {"name": data["name"], "w": data["w"], "h": data["h"], "widgets": []})
            assert len(layout["widgets"]) + 1 == data["offset"], "layout batches must be ordered"
            layout["widgets"].extend(data["widgets"])
    elif re.search(r"\[(?:\w+Tests|\w+Checks|EngagementRules|EngagementVariants)\]", text):
        markers.append(text.strip())
assert markers, "missing Lua completion markers"
project = Path(result["project_realpath"])
hashes = {str(p.relative_to(project)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in sorted((project / "scripts").rglob("*.lua"))}
summary = {"run_id": result["run_id"], "entry": report["script"], "result": report["result"],
           "native_errors": report["summary"], "windowless": True, "silent": True,
           "engine_test_result": report["test_result"],
           "engine_test_assertions": report["test_assertions"],
           "lua_completion_markers": markers, "runs": runs, "fusion": fusion, "recipe_scenarios": recipes,
           "ui_layout_names": list(layouts),
           "source_sha256_at_collection": hashes,
           "limitations": "Ordinary Lua asserts and synthetic input policies; no human enjoyment verdict or GPU screenshot. Source hashes record collection time."}
args.out.mkdir(parents=True, exist_ok=True)
(args.out / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
for name, layout in layouts.items():
    (args.out / f"{name}-layout.json").write_text(json.dumps(layout, ensure_ascii=False), encoding="utf-8")
print(json.dumps({"run_id": result["run_id"], "runs": len(runs), "fusion": len(fusion),
                  "layouts": len(layouts), "out": str(args.out)}, ensure_ascii=False))
