"""Writes this chunk's puzzle ids, split across W worker files: ids[chunk::of], then round-robin over workers.
Split 'practice' takes the ids of practice_puzzles.csv (next to split.json)."""
import csv
import json
import sys
from pathlib import Path

split_file, split, chunk, of, workers, prefix = sys.argv[1:7]
if split.startswith(("progs:", "feat:", "pz:")):  # pz: = build (elfgen) only the bundle's puzzle ids
    ids = [l.split("\t", 1)[0] for l in open(Path(sys.argv[7]) / "progs" / "programs.tsv") if "\t" in l]
elif split.startswith("synth:"):
    ids = [r["id"] for r in csv.DictReader(open(Path(sys.argv[7]) / "synth" / "puzzles.csv", newline=""))]
elif split == "practice":
    ids = [r["id"] for r in csv.DictReader(open(Path(split_file).parent / "practice_puzzles.csv", newline=""))]
else:
    s = json.load(open(split_file))
    ids = sorted(s["train"] + s["dev"] + s["test"]) if split == "all" else s[split]
mine = ids[int(chunk)::int(of)]
for w in range(int(workers)):
    with open(f"{prefix}_{w}.txt", "w") as f:
        f.write("\n".join(mine[w::int(workers)]) + "\n")
