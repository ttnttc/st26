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
case " $PARAMS " in *" policy="*|*" vmodel="*|*" model="*|*" hub_file="*|*" root_model="*)  # learned scorers ship encrypted; policy=/vmodel=<name> resolve inside the bundle
  mkdir -p "$PZ/models"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:ST26_DATA_KEY -in data/models.enc | tar -xzf - -C "$PZ/models"
  PARAMS=$(echo " $PARAMS" | sed "s# policy=# policy=$PZ/models/#g; s# vmodel=# vmodel=$PZ/models/#g; s# model=# model=$PZ/models/#g; s# hub_file=# hub_file=$PZ/models/#g; s# root_model=# root_model=$PZ/models/#g") ;;
esac
PFILE="$PZ/puzzles.csv"
[ "$SPLIT" = "practice" ] && PFILE="$PZ/practice_puzzles.csv"
case "$SPLIT" in progs:*|feat:*)
  PN="${SPLIT#*:}"; mkdir -p "$PZ/progs"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:ST26_DATA_KEY -in "data/progs_$PN.enc" | tar -xzf - -C "$PZ/progs"
  if [ -f "$PZ/progs/puzzles.csv" ]; then PFILE="$PZ/progs/puzzles.csv"; fi ;;  # bundle brings its own (synthetic) puzzles
esac
case "$SPLIT" in synth:*)
  SN="${SPLIT#synth:}"; mkdir -p "$PZ/synth"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:ST26_DATA_KEY -in "data/$SN.enc" | tar -xzf - -C "$PZ/synth"
  PFILE="$PZ/synth/puzzles.csv" ;;
esac
# workers stop 15 min before the job limit so the finished puzzles are still packaged (outputs are per puzzle)
TL="timeout $(( ${JOB_MINUTES:-330} * 60 - 900 ))s"
python3 -I jobs/select_ids.py "$PZ/split.json" "$SPLIT" "$CHUNK" "$OF" 4 work/ids "$PZ"
for w in 0 1 2 3; do
  case "$SPLIT" in
    progs:*)  # LNS mode: improve the given programs
      awk -F'\t' 'NR==FNR { if ($0 != "") keep[$0] = 1; next } ($1 in keep)' "work/ids_$w.txt" \
          "$PZ/progs/programs.tsv" > "work/in_$w.tsv"
      case " $PARAMS " in *" ext="*)  # external polishing engine (triwalk | sa): ext=<name> secs=<s> [seed=] [slack=]
        X=$(echo " $PARAMS" | sed -n 's/.* ext=\([a-z]*\).*/\1/p'); XS=$(echo " $PARAMS" | sed -n 's/.* secs=\([0-9.]*\).*/\1/p')
        XD=$(echo " $PARAMS" | sed -n 's/.* seed=\([0-9]*\).*/\1/p'); XK=$(echo " $PARAMS" | sed -n 's/.* slack=\([0-9]*\).*/\1/p')
        ( ulimit -v 3500000; $TL python3 -I jobs/ext_engine.py "$X" "$PFILE" "work/in_$w.tsv" "${XS:-60}" "${XD:-$w}" "${XK:-2}" \
            > "work/out_$w.tsv" 2> "work/stat_$w.tsv" ) &
        continue ;;
      esac
      PT=bin/elflns; case " $PARAMS " in *" mode=cone "*|*" mode=suffix "*|*" mode=pair "*|*" mode=rootfeat "*|*" mode=rootrank "*|*" mode=prefix "*) PT=bin/elfsuffix ;; esac  # exact repair
      ( ulimit -v 3500000; $TL $PT "$PFILE" "work/in_$w.tsv" $PARAMS > "work/out_$w.tsv" 2> "work/stat_$w.tsv" ) & ;;
    feat:*)  # dataset mode: elffeat over the given (expert) programs
      awk -F'\t' 'NR==FNR { if ($0 != "") keep[$0] = 1; next } ($1 in keep)' "work/ids_$w.txt" \
          "$PZ/progs/programs.tsv" > "work/in_$w.tsv"
      ( ulimit -v 3500000; $TL bin/elffeat "$PFILE" "work/in_$w.tsv" $PARAMS > "work/out_$w.tsv" 2> "work/stat_$w.tsv" ) & ;;
    *)
      TR=""; TOOL=bin/elfgen
      case " $PARAMS " in *" roll_states="*) TOOL=bin/elfroll ;; *" c_mode=2 "*|*" pal_search=1 "*) TR="trace=work/trace_$w.jsonl" ;; esac
      ( ulimit -v 3500000; $TL $TOOL "$PFILE" "work/ids_$w.txt" $PARAMS $TR > "work/out_$w.tsv" 2> "work/stat_$w.tsv" ) & ;;
  esac
done
wait
echo "nproc $(nproc) cfg $CFG chunk $CHUNK/$OF" > work/meta.txt
tar -czf work/result.tar.gz -C work meta.txt $(cd work && ls out_*.tsv stat_*.tsv trace_*.jsonl 2>/dev/null)
openssl cms -encrypt -binary -aes256 -in work/result.tar.gz -outform DER -out out/result.cms keys/st26_cert.pem
rm -rf work "$PZ"
echo "gen: done"
