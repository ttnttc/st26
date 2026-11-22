#!/usr/bin/env bash
# One generation chunk: decrypt inputs and config, run 4 workers of bin/elfgen on this chunk's puzzles,
# encrypt everything that leaves the runner. The public log shows step names and a done line only.
set -euo pipefail
: "${ST26_DATA_KEY:?missing}"
PZ="$RUNNER_TEMP/pz"
mkdir -p "$PZ" work out
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:ST26_DATA_KEY -in data/puzzles.enc | tar -xzf - -C "$PZ"
PARAMS=$(echo "$CONFIGS" | base64 -d | openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -pass env:ST26_DATA_KEY \
         | python3 -I -c "import json,sys; print(json.load(sys.stdin)['$CFG'])")
chmod +x bin/*
PFILE="$PZ/puzzles.csv"
[ "$SPLIT" = "practice" ] && PFILE="$PZ/practice_puzzles.csv"
case "$SPLIT" in progs:*)
  PN="${SPLIT#progs:}"; mkdir -p "$PZ/progs"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:ST26_DATA_KEY -in "data/progs_$PN.enc" | tar -xzf - -C "$PZ/progs" ;;
esac
case "$SPLIT" in synth:*)
  SN="${SPLIT#synth:}"; mkdir -p "$PZ/synth"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:ST26_DATA_KEY -in "data/$SN.enc" | tar -xzf - -C "$PZ/synth"
  PFILE="$PZ/synth/puzzles.csv" ;;
esac
python3 -I jobs/select_ids.py "$PZ/split.json" "$SPLIT" "$CHUNK" "$OF" 4 work/ids "$PZ"
for w in 0 1 2 3; do
  case "$SPLIT" in
    progs:*)  # LNS mode: improve the given programs
      awk -F'\t' 'NR==FNR { if ($0 != "") keep[$0] = 1; next } ($1 in keep)' "work/ids_$w.txt" \
          "$PZ/progs/programs.tsv" > "work/in_$w.tsv"
      ( ulimit -v 3500000; bin/elflns "$PFILE" "work/in_$w.tsv" $PARAMS > "work/out_$w.tsv" 2> "work/stat_$w.tsv" ) & ;;
    *)
      TR=""
      case " $PARAMS " in *" c_mode=2 "*) TR="trace=work/trace_$w.jsonl" ;; esac
      ( ulimit -v 3500000; bin/elfgen "$PFILE" "work/ids_$w.txt" $PARAMS $TR > "work/out_$w.tsv" 2> "work/stat_$w.tsv" ) & ;;
  esac
done
wait
echo "nproc $(nproc) cfg $CFG chunk $CHUNK/$OF" > work/meta.txt
tar -czf work/result.tar.gz -C work meta.txt $(cd work && ls out_*.tsv stat_*.tsv trace_*.jsonl 2>/dev/null)
openssl cms -encrypt -binary -aes256 -in work/result.tar.gz -outform DER -out out/result.cms keys/st26_cert.pem
rm -rf work "$PZ"
echo "gen: done"
