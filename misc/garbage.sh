#!/bin/zsh

# Next New Taipei City trash truck time for an address, plus a live ETA when
# the truck is actually out on the route.
#
# Usage:
#   garbage                  Next collection for your default address
#   garbage --full           Weekly schedule table
#   garbage --address ADDR   Query a different address
#   garbage --refresh        Re-download the route dataset
#
# Your default address lives in ~/.config/ntpc-trash/address so it stays out
# of this repo. Data: New Taipei City open data platform (data.ntpc.gov.tw).

set -euo pipefail

readonly ROUTE_URL='https://data.ntpc.gov.tw/api/datasets/edc3ad26-8ae7-4916-a00b-bc6048d19bf8/json'
readonly LIVE_URL='https://data.ntpc.gov.tw/api/datasets/28ab4122-60e1-4065-98e5-abccb69aaca6/json?page=0&size=500'
readonly ROUTE_PAGES=27
readonly UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'

readonly CONFIG_FILE="$HOME/.config/ntpc-trash/address"
readonly CACHE_DIR="$HOME/.cache/ntpc-trash"
readonly CACHE_JSON="$CACHE_DIR/routes.json"
readonly CACHE_MAX_AGE=$((7 * 24 * 3600))

readonly LIVE_BEFORE_MIN=90   # fetch live data if the next collection is within this
readonly LATE_GRACE_MIN=40    # ...or if a collection passed at most this long ago

usage() {
  print -r -- 'Usage: garbage [options]

  (no options)          Next collection time for your default address
  -f, --full            Full weekly schedule table
  -a, --address ADDR    Query a different address (e.g. 板橋區文化路一段100號)
      --refresh         Force re-download of the route dataset
  -h, --help            This help

Your default address is read from ~/.config/ntpc-trash/address (one line,
e.g. 金城路2段245巷19號). Keep it there, not in this repo.'
}

jqf() { printf '%s' "$2" | jq -r "$1"; }

fmt_hhmm() { printf '%02d:%02d' $(($1 / 60)) $(($1 % 60)); }

fmt_in() {  # $1 = minutes from now
  local m=$1
  if (( m >= 60 )); then
    if (( m % 60 == 0 )); then echo "in $((m / 60))h"; else echo "in $((m / 60))h $((m % 60))m"; fi
  else
    echo "in ${m}m"
  fi
}

day_label() {  # $1 = days ahead, $2 = weekday (0=Sun)
  if (( $1 == 0 )); then echo "today"
  elif (( $1 == 1 )); then echo "tomorrow"
  else date -v+"$1"d +%a
  fi
}

# ── arguments ─────────────────────────────────────────

full=0
refresh=0
address=''

while (( $# > 0 )); do
  case $1 in
    -f|--full) full=1 ;;
    -a|--address)
      shift
      address=${1:-}
      [[ -n $address ]] || { echo "Error: --address needs a value." >&2; exit 1 }
      ;;
    --refresh) refresh=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [[ -z $address ]]; then
  if [[ -r $CONFIG_FILE ]]; then
    address=$(<"$CONFIG_FILE")
  else
    echo "Error: no default address configured." >&2
    echo "Create $CONFIG_FILE with your address on one line, or pass --address." >&2
    exit 1
  fi
fi
address=${address//[[:space:]]/}   # strip whitespace/newlines

# ── route cache ───────────────────────────────────────

refresh_cache() {
  echo "Downloading route dataset ($ROUTE_PAGES pages)..." >&2
  mkdir -p "$CACHE_DIR"
  local tmp="$CACHE_JSON.tmp"
  local pages=() p out rtype
  for p in $(seq 0 $((ROUTE_PAGES - 1))); do
    out=$(curl -sL --max-time 90 -A "$UA" "$ROUTE_URL?page=$p&size=1000") || {
      echo "Error: download failed on page $p." >&2
      return 1
    }
    rtype=$(printf '%s' "$out" | jq -r 'type' 2>/dev/null) || rtype=''
    [[ $rtype == array ]] || {
      echo "Error: unexpected response on page $p (upstream rejected?)." >&2
      return 1
    }
    pages+=("$out")
  done
  printf '%s\n' "${pages[@]}" | jq -s '
    [ .[][] | {
        lineid, linename, name, village, city, time,
        rank: (.rank | tonumber),
        lat: (.latitude | tonumber),
        lon: (.longitude | tonumber),
        days: ([.garbagesunday, .garbagemonday, .garbagetuesday, .garbagewednesday,
                .garbagethursday, .garbagefriday, .garbagesaturday
                | if . == "Y" then "1" else "0" end] | join(""))
      } ]' > "$tmp"
  mv "$tmp" "$CACHE_JSON"
  echo "Cached $(jq length < "$CACHE_JSON") stops." >&2
}

if (( refresh )) || [[ ! -f $CACHE_JSON ]] || \
   (( $(date +%s) - $(stat -f %m "$CACHE_JSON") > CACHE_MAX_AGE )); then
  refresh_cache
fi

# ── match the address ─────────────────────────────────

matches=$(jq -c --arg q "$address" '[.[] | select(.name | contains($q))]' "$CACHE_JSON")
match_count=$(printf '%s' "$matches" | jq 'length')
if (( match_count == 0 )); then
  echo "No collection stops match \"$address\"." >&2
  echo "Try a shorter address (e.g. drop the alley or house number)." >&2
  exit 1
fi
uniq_names=$(printf '%s' "$matches" | jq '[.[].name] | unique | length')

# ── time context ──────────────────────────────────────

now_h=$(date +%H)
now_m=$(date +%M)
now_min=$((10#$now_h * 60 + 10#$now_m))
today_wd=$(date +%w)

# ── next collection ───────────────────────────────────

next=$(printf '%s' "$matches" | jq -c --argjson wd "$today_wd" --argjson now "$now_min" '
  def tmin: (.time | split(":") | map(tonumber) | .[0] * 60 + .[1]);
  [ range(0; 8) as $d
    | (($wd + $d) % 7) as $w
    | .[] | select(.days[$w:$w+1] == "1")
    | (tmin) as $tm
    | select(($d > 0) or ($tm > $now))
    | {d: $d, wd: $w, min: $tm, lineid, linename, name, rank, time, village, city, lat, lon}
  ] | sort_by(.d, .min) | .[0] // empty')

# ── a collection that just passed (truck may still be running late) ──

late=$(printf '%s' "$matches" | jq -c --argjson wd "$today_wd" --argjson now "$now_min" --argjson grace "$LATE_GRACE_MIN" '
  def tmin: (.time | split(":") | map(tonumber) | .[0] * 60 + .[1]);
  [ .[] | select(.days[$wd:$wd+1] == "1")
    | (tmin) as $tm
    | select($tm <= $now and ($now - $tm) <= $grace)
    | {d: 0, wd: $wd, min: $tm, lineid, linename, name, rank, time, village, city, lat, lon}
  ] | sort_by(.min) | .[-1] // empty')

# ── live GPS (best effort) ────────────────────────────

need_live=0
if [[ -n $late ]]; then
  need_live=1
elif [[ -n $next ]]; then
  if (( $(jqf '.d' "$next") == 0 )) && \
     (( $(jqf '.min' "$next") - now_min <= LIVE_BEFORE_MIN )); then
    need_live=1
  fi
fi

live=''
if (( need_live )); then
  live=$(curl -sL --max-time 10 -A "$UA" "$LIVE_URL" 2>/dev/null) || live=''
  [[ $(printf '%s' "$live" | jq -r 'type' 2>/dev/null) == array ]] || live=''
fi

# Echo live status for a target stop, or return 1 when no truck is out.
live_status() {  # $1 = target JSON with lineid, rank, min
  local target=$1 lineid trucks stops
  lineid=$(jqf '.lineid' "$target")
  trucks=$(printf '%s' "$live" | jq -c --arg l "$lineid" '[.[] | select(.lineid == $l)]')
  [[ $(printf '%s' "$trucks" | jq 'length') -gt 0 ]] || return 1
  stops=$(jq -c --arg l "$lineid" '[.[] | select(.lineid == $l) | {rank, name, time, lat, lon}]' "$CACHE_JSON")
  printf '%s' "$trucks" | jq -c --argjson target "$target" --argjson stops "$stops" '
    def tmin: split(":") | map(tonumber) | .[0] * 60 + .[1];
    def hav($a; $o; $la; $lo):
      (($la - $a) * 3.14159265 / 180) as $dl
      | (($lo - $o) * 3.14159265 / 180) as $dn
      | (($dl / 2 | sin) * ($dl / 2 | sin)
         + ($a * 3.14159265 / 180 | cos) * ($la * 3.14159265 / 180 | cos)
         * ($dn / 2 | sin) * ($dn / 2 | sin)) as $h
      | 6371 * 2 * ($h | sqrt | asin);
    [ .[]
      | . as $t
      | ($t.latitude | tonumber) as $la
      | ($t.longitude | tonumber) as $lo
      | ($stops | sort_by(hav($la; $lo; .lat; .lon)) | .[0]) as $near
      | { car: $t.car,
          near_rank: $near.rank,
          near_name: $near.name,
          delay: (($t.time | split(" ")[1] | tmin) - ($near.time | tmin)) }
    ] | sort_by(.near_rank) as $loc
    | ([ $loc[] | select(.near_rank <= $target.rank) ] | last) as $p
    | if $p then
        { car: $p.car, near_name: $p.near_name,
          stops_away: ($target.rank - $p.near_rank),
          eta: ($target.min + $p.delay), delay: $p.delay, passed: false }
      else
        { car: ($loc[-1].car // "?"), passed: true }
      end'
}

# ── output ────────────────────────────────────────────

if (( full )); then
  echo "🗑  Schedules matching \"$address\""
  next_key=''
  [[ -n $next ]] && next_key="$(jqf '.lineid' "$next") $(jqf '.time' "$next")"
  printf '%s' "$matches" | jq -r --arg nextkey "$next_key" '
    def tmin: (.time | split(":") | map(tonumber) | .[0] * 60 + .[1]);
    ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"] as $w
    | group_by(.name)[]
    | .[0] as $s
    | "",
      "\($s.name) (\($s.city) \($s.village))",
      ( sort_by(tmin)[]
        | .days as $d
        | "  \(.linename)  \(.time)  "
          + (if $d == "1111111" then "Every day"
             else [range(0;7) as $i | select($d[$i:$i+1] == "1") | $w[$i]] | join(" ")
             end)
          + (if "\(.lineid) \(.time)" == $nextkey then "  ← next" else "" end) )
  '
  exit 0
fi

if [[ -z $next ]]; then
  echo "No collection found in the next 8 days for \"$address\"."
  exit 0
fi

if (( uniq_names > 1 )); then
  echo "$uniq_names stops match \"$address\"; showing the earliest next (see all with --full)."
fi

# A collection that just passed but whose truck is still on the way.
if [[ -n $late && -n $live ]]; then
  st=$(live_status "$late" || true)
  if [[ -n $st ]] && [[ $(jqf '.passed' "$st") == false ]]; then
    eta=$(jqf '.eta' "$st")
    (( eta < now_min )) && eta=$now_min
    echo "⏰ Still time! $(jqf '.time' "$late") $(jqf '.linename' "$late") is running late — $(jqf '.car' "$st") near $(jqf '.near_name' "$st"), $(jqf '.stops_away' "$st") stops away, ETA ~$(fmt_hhmm $eta)"
  fi
fi

n_d=$(jqf '.d' "$next")
n_min=$(jqf '.min' "$next")
msg="🗑  Next: $(day_label "$n_d" "$(jqf '.wd' "$next")") $(jqf '.time' "$next")"
(( n_d == 0 )) && msg+=" ($(fmt_in $((n_min - now_min))))"
msg+=" · $(jqf '.linename' "$next") · $(jqf '.name' "$next")"
echo "$msg"

# Live ETA for the next collection, when the truck is out.
if [[ -n $live ]]; then
  st=$(live_status "$next" || true)
  if [[ -n $st ]]; then
    if [[ $(jqf '.passed' "$st") == true ]]; then
      echo "   Live: truck already passed this stop"
    else
      eta=$(jqf '.eta' "$st")
      (( eta < now_min )) && eta=$now_min
      delay=$(jqf '.delay' "$st")
      note="on time"
      (( delay > 2 )) && note="$delay min late"
      (( delay < -2 )) && note="$((-delay)) min early"
      echo "   Live: $(jqf '.car' "$st") near $(jqf '.near_name' "$st") · $(jqf '.stops_away' "$st") stops away · ETA ~$(fmt_hhmm $eta) ($note)"
    fi
  fi
fi
