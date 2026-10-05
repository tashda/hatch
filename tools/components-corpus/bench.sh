#!/bin/bash
# Scores the inventory's places against controls a reader judged in the corpus (two samples: the one the rules were
# tuned on and a held-out one). Usage: tools/components-corpus/bench.sh <corpus folder> [heldout|tuned] [-v]
# The corpus comes from fetch.sh; Hatch's own app and Echo are read from their clones (hatch-app, echo).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
CORPUS="${1:?Usage: bench.sh <corpus folder> [heldout|tuned] [-v]}"; WHICH="${2:-heldout}"; VERBOSE="${3:-}"
ECHO_DIR="${ECHO_DIR:-$HOME/Development/Echo}"
(cd "$ROOT" && swift build -q --product hatch) || exit 1
OUT=$(mktemp -d)
for app in $(python3 -c "import json;print(' '.join(sorted({r['app'] for r in json.load(open('$HERE/gold-$WHICH.json'))})))"); do
  dir="$CORPUS/$app"; [ "$app" = "hatch-app" ] && dir="$ROOT/App"; [ "$app" = "echo" ] && dir="$ECHO_DIR"
  [ -d "$dir" ] || continue
  "$ROOT/.build/debug/hatch" components inventory "$dir" --json > "$OUT/$app.json" 2>/dev/null &
done
wait
python3 - "$HERE/gold-$WHICH.json" "$OUT" "$VERBOSE" <<'PY'
import json,sys,os,collections
gold=json.load(open(sys.argv[1])); out=sys.argv[2]; verbose=sys.argv[3]=='-v'
ok=0; n=0; per=collections.defaultdict(lambda:[0,0]); wrong=[]
for g in gold:
    f=os.path.join(out,g['app']+'.json')
    if not os.path.exists(f): continue
    uses=json.load(open(f)).get('uses',[])
    u=[x for x in uses if x['file']==g['file'] and x['line']==g['line'] and x['element']==g['element']]
    if not u: continue
    p=u[0]['place'] or 'UNKNOWN'; e=u[0].get('evidence','?')
    n+=1; ok+=p==g['place']; per[e][1]+=1; per[e][0]+=p==g['place']
    if p!=g['place']: wrong.append((g['id'],g['app'],g['file'],g['line'],p,g['place'],g['note']))
print(f"place accuracy {ok}/{n} = {100*ok/max(n,1):.0f}%")
print("by evidence:", {e:f"{a}/{b}" for e,(a,b) in per.items()})
if verbose:
    for w in wrong: print(' ', *w)
PY
rm -rf "$OUT"
