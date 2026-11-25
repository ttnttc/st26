"""Run an external polishing engine (triwalk or sa) on a chunk of programs; print improved programs as TSV.

    python3 -I jobs/ext_engine.py <triwalk|sa> <puzzles.csv> <programs.tsv> <seconds per puzzle> [seed] [slack]

programs.tsv: id \\t ... \\t program (JSON, the last column). Output: id \\t start_len \\t new_len \\t program (JSON).
Only strictly shorter programs are printed; they are re-validated locally after collection.
"""
import csv
import json
import subprocess
import sys
import tempfile

csv.field_size_limit(10**9)
engine, pfile, progs, secs = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
seed = sys.argv[5] if len(sys.argv) > 5 else "1"
slack = sys.argv[6] if len(sys.argv) > 6 else "2"
P = {}
for r in csv.DictReader(open(pfile, newline="")):
    P[r["id"]] = (json.loads(r["starting_values"]), json.loads(r["targets"]), int(r["value_limit"]), int(r["registers"]))
rows = []
for line in open(progs):
    f = line.rstrip("\n").split("\t")
    if f[0] in P:
        rows.append((f[0], json.loads(f[-1])))
OPS = {"+": 0, "-": 1, "*": 2, "/": 3}
INV = "+-*/"


def emit(pid, n0, prog):
    print(pid, n0, len(prog), json.dumps(prog, separators=(",", ":")), sep="\t", flush=True)


if engine == "triwalk":
    for pid, prog in rows:  # one puzzle per process: a crash or timeout loses only that puzzle
        s, t, L, R = P[pid]
        txt = f"P {pid} {len(s)} {' '.join(map(str, s))} {len(t)} {' '.join(map(str, t))} {L} {R} {len(prog)}\n"
        txt += "".join(f"{op} {i} {j} {d}\n" for op, i, j, d in prog)
        try:
            r = subprocess.run(["bin/triwalk", "--time", str(secs), "--seed", seed], input=txt, capture_output=True,
                               text=True, timeout=secs * 4 + 60)
        except subprocess.TimeoutExpired:
            continue
        lines = r.stdout.split("\n")
        k = 0
        while k < len(lines):
            h = lines[k].split()
            if len(h) == 4 and h[0] == "R":
                n = int(h[3])
                body = [x.split() for x in lines[k + 1:k + 1 + n]]
                emit(h[1], int(h[2]), [[b[0], int(b[1]), int(b[2]), int(b[3])] for b in body])
                k += 1 + n
            elif len(h) == 4 and h[0] == "V":
                k += 1 + int(h[3])
            else:
                k += 1
elif engine == "sa":
    for pid, prog in rows:
        s, t, L, R = P[pid]
        with tempfile.NamedTemporaryFile("w", suffix=".bank", delete=False) as fb:
            fb.write(f"P {pid} {L} {R}\nS {len(s)} {' '.join(map(str, s))}\nT {len(t)} {' '.join(map(str, t))}\n")
            fb.write(f"G {len(prog)} " + " ".join(f"{OPS[op]} {i} {j} {d}" for op, i, j, d in prog) + "\n")
            bank = fb.name
        out = bank + ".out"
        try:
            subprocess.run(["bin/sa", bank, out, str(secs), "0", "1", "-", slack], capture_output=True, text=True,
                           timeout=secs * 4 + 60, env={"SA_SEED": seed})
        except subprocess.TimeoutExpired:
            continue
        try:
            for line in open(out):
                h = line.split()
                if len(h) >= 3 and h[0] == "R":
                    n = int(h[2])
                    v = list(map(int, h[3:3 + 4 * n]))
                    emit(h[1], len(prog), [[INV[v[4 * q]], v[4 * q + 1], v[4 * q + 2], v[4 * q + 3]] for q in range(n)])
        except FileNotFoundError:
            pass
