"""Random synthetic puzzles for the probe: a random forward program from random seeds; targets are some of the
values it produced. Cells are the program itself or simple corruptions of it. Generic test data only."""
import csv
import json
import random
import sys
from pathlib import Path

out, n = Path(sys.argv[1]), int(sys.argv[2])
rng = random.Random(1)
puzzles, cells = [], []
for k in range(max(1, n // 50)):
    seeds = [rng.randrange(2, 2000) for _ in range(rng.randrange(1, 6))]
    regs = seeds + [None] * (48 - len(seeds))
    prog, made = [], []
    limit = 10**18
    while len(prog) < rng.randrange(20, 200):
        live = [i for i, v in enumerate(regs) if v is not None]
        i, j, d = rng.choice(live), rng.choice(live), rng.randrange(48)
        op = rng.choice("+-*/")
        a, b = regs[i], regs[j]
        r = a + b if op == "+" else a - b if op == "-" else a * b if op == "*" else (a // b if a % b == 0 else 0)
        if 0 < r <= limit:
            regs[d] = r
            prog.append([op, i, j, d])
            made.append(r)
    targets = sorted(set(rng.sample(made, min(len(made), 30))))
    pid = f"syn_{k:06d}"
    puzzles.append((pid, seeds, targets, limit))
    for m in range(50):
        p = [list(x) for x in prog]
        if m % 2:
            p[rng.randrange(len(p))][rng.randrange(1, 4)] = rng.randrange(48)
        cells.append((pid, json.dumps(p, separators=(",", ":"))))
with open(out / "puzzles.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["id", "starting_values", "targets", "value_limit", "registers"])
    for pid, s, t, lim in puzzles:
        w.writerow([pid, json.dumps(s), json.dumps(t), lim, 48])
with open(out / "cells.tsv", "w") as f:
    f.writelines(f"{pid}\t{c}\n" for pid, c in cells)
print(f"puzzles {len(puzzles)}, cells {len(cells)}")
