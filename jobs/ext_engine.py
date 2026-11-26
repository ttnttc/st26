"""Run an external polishing engine (triwalk or sa) on a chunk of programs; print improved programs as TSV.

    python3 -I jobs/ext_engine.py <triwalk|tchain|sa> <puzzles.csv> <programs.tsv> <seconds per puzzle> [seed] [slack] [triwalk flags k:v,k:v]

programs.tsv: id \\t ... \\t program (JSON, the last column). Output: id \\t start_len \\t new_len \\t program (JSON).
Only strictly shorter programs are printed; they are re-validated locally after collection.
tchain: slice k runs <seconds> * 2^min(k-1, 6), [slack] = number of slices; output id \\t slice \\t len \\t program (slice 0 = start).
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
targs = [x for kv in (sys.argv[7].split(",") if len(sys.argv) > 7 and sys.argv[7] else []) for x in ("--" + kv.split(":")[0], kv.split(":")[1])]
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


def triwalk(pid, prog, secs, seed):
    """one triwalk process on one puzzle; returns the programs it reports (R blocks)"""
    s, t, L, R = P[pid]
    txt = f"P {pid} {len(s)} {' '.join(map(str, s))} {len(t)} {' '.join(map(str, t))} {L} {R} {len(prog)}\n"
    txt += "".join(f"{op} {i} {j} {d}\n" for op, i, j, d in prog)
    try:
        r = subprocess.run(["bin/triwalk", "--time", str(secs), "--seed", str(seed)] + targs, input=txt, capture_output=True,
                           text=True, timeout=secs * 4 + 60)
    except subprocess.TimeoutExpired:
        return []
    lines = r.stdout.split("\n")
    out, k = [], 0
    while k < len(lines):
        h = lines[k].split()
        if len(h) == 4 and h[0] == "R":
            n = int(h[3])
            body = [x.split() for x in lines[k + 1:k + 1 + n]]
            out.append((h[1], int(h[2]), [[b[0], int(b[1]), int(b[2]), int(b[3])] for b in body]))
            k += 1 + n
        elif len(h) == 4 and h[0] == "V":
            k += 1 + int(h[3])
        else:
            k += 1
    return out


if engine == "triwalk":
    for pid, prog in rows:  # one puzzle per process: a crash or timeout loses only that puzzle
        for rid, n0, p in triwalk(pid, prog, secs, seed):
            emit(rid, n0, p)
elif engine == "tchain":  # improvement trajectories (G0 pairs): `slack` short slices per puzzle, each from the last best
    nsl = int(slack)
    for pid, prog in rows:
        best = prog
        emit(pid, 0, best)  # slice 0 = the start program, so every pair can be rebuilt from this output alone
        for k in range(1, nsl + 1):
            got = [p for rid, _, p in triwalk(pid, best, secs * 2 ** min(k - 1, 6), int(seed) * 1000 + k) if rid == pid and len(p) < len(best)]
            if got:
                best = min(got, key=len)
                emit(pid, k, best)
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
