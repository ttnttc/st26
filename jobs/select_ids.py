"""Writes this chunk's puzzle ids, split across W worker files: ids[chunk::of], then round-robin over workers."""
import json
import sys

split_file, split, chunk, of, workers, prefix = sys.argv[1:7]
s = json.load(open(split_file))
ids = sorted(s["train"] + s["dev"] + s["test"]) if split == "all" else s[split]
mine = ids[int(chunk)::int(of)]
for w in range(int(workers)):
    with open(f"{prefix}_{w}.txt", "w") as f:
        f.write("\n".join(mine[w::int(workers)]) + "\n")
