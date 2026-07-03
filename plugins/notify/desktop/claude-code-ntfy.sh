#!/usr/bin/env bash
#
# claude-code-ntfy — interactive multi-topic ntfy → macOS notification bridge.
#
# Run it, type an ntfy topic (or a full https URL) at the prompt, press Enter,
# and it spawns a background `ntfy sub` listener for that link. Every incoming
# ntfy message is parsed and popped as a native macOS notification (its own
# title + message). Add as many links as you like — they're shown as a numbered
# list as you go. Listeners are spawned by this script and ALL torn down when
# you quit (q / Ctrl-C / Ctrl-D) or the script is killed.
#
# Usage:
#   claude-code-ntfy                    # interactive manager
#   claude-code-ntfy <topic|url> ...    # pre-load link(s), then go interactive
#   claude-code-ntfy --parse            # (internal/test) read ntfy NDJSON on stdin, notify
#   claude-code-ntfy -h | --help
#
# Notes:
#   * On start the script auto-subscribes to the notify plugin's configured
#     topic, if it finds one. Resolution mirrors the sender (first hit wins):
#     $NTFY_TOPIC, $NTFY_TOPIC_FILE, then ../.config/topic RELATIVE TO THIS
#     SCRIPT (symlinks resolved) — the file `/notify` writes, which sits next
#     to desktop/ inside the plugin folder. A copy of the script living
#     outside the plugin folder finds no such file and starts empty.
#   * A "link" may be a bare topic (e.g. claude-code-usyawcrtus07) — it's
#     assumed to live on https://ntfy.sh — or a full http(s):// URL for a
#     self-hosted server.
#   * Each listener runs in its OWN process group so the ntfy process and its
#     JSON parser are killed together on teardown; nothing is left orphaned.

DEFAULT_SERVER="https://ntfy.sh"
PLACEHOLDER="REPLACE_ME_WITH_A_PRIVATE_NTFY_TOPIC"
LOG="${TMPDIR:-/tmp}/claude-code-ntfy.$$.log"

# Parallel arrays — one slot per active listener.
URLS=()     # normalized subscription URL
LPIDS=()    # pid of the parser (last stage of the pipeline) — used for liveness
PGIDS=()    # process-group id of the whole listener — used to kill it

_SHUTDOWN_DONE=""

# ---------------------------------------------------------------------------
# notification backends
# ---------------------------------------------------------------------------

fire_notification() {
  # $1 = title, $2 = message.
  # Values are handed to AppleScript as argv (NOT interpolated into the script
  # text) so quotes / backslashes in a message can't break or inject into it.
  local title="$1" message="$2"
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$message" -sound default >/dev/null 2>&1
  else
    osascript - "$title" "$message" >/dev/null 2>&1 <<'OSA'
on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
end run
OSA
  fi
}

parse_stream() {
  # Reads an ntfy JSON stream (NDJSON, one object per line) on stdin and fires
  # a native notification for every real message. Non-message events
  # (open / keepalive / poll_request) are dropped. --unbuffered => live.
  jq --unbuffered -rc \
    'select(.event == "message")
     | [(.title // "ntfy"), (.message // "")]
     | @tsv' 2>/dev/null \
  | while IFS=$'\t' read -r title message; do
      fire_notification "$title" "$message"
    done
}

# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"   # left
  s="${s%"${s##*[![:space:]]}"}"   # right
  printf '%s' "$s"
}

normalize_url() {
  # bare topic -> https://ntfy.sh/<topic> ; leave real URLs alone.
  local in
  in="$(trim "$1")"
  case "$in" in
    http://*|https://*) printf '%s' "$in" ;;
    ntfy.sh/*)          printf 'https://%s' "$in" ;;
    *)                  printf '%s/%s' "$DEFAULT_SERVER" "$in" ;;
  esac
}

# ---------------------------------------------------------------------------
# width-aware display helpers — everything below adapts to the terminal width
# so nothing wraps into garbage on a narrow pane.
# ---------------------------------------------------------------------------

term_width() {
  local w
  w="$(tput cols 2>/dev/null)"
  case "$w" in ''|*[!0-9]*) w="${COLUMNS:-}" ;; esac
  case "$w" in ''|*[!0-9]*) w=80 ;; esac
  [ "$w" -lt 1 ] && w=80
  printf '%s' "$w"
}

# horizontal rule sized to the terminal (capped so it isn't huge when wide).
hr() {
  local w; w="$(term_width)"
  [ "$w" -gt 56 ] && w=56
  printf '%*s\n' "$w" '' | tr ' ' '-'
}

# truncate keeping the HEAD, add a trailing ellipsis when cut (for prose).
fit_head() {
  local s="$1" w="$2"
  [ "$w" -lt 1 ] && w=1
  [ "${#s}" -le "$w" ] && { printf '%s' "$s"; return; }
  [ "$w" -le 1 ] && { printf '%.*s' "$w" "$s"; return; }
  printf '%s…' "${s:0:$((w - 1))}"
}

# truncate keeping the TAIL (for URLs/paths — the meaningful part is the end).
fit_tail() {
  local s="$1" w="$2"
  [ "$w" -lt 1 ] && w=1
  [ "${#s}" -le "$w" ] && { printf '%s' "$s"; return; }
  [ "$w" -le 1 ] && { printf '%s' "${s: -1}"; return; }
  printf '…%s' "${s: -$((w - 1))}"
}

# print one prose line, truncated so it never wraps.
say() { printf '%s\n' "$(fit_head "$1" "$(term_width)")"; }

# print "<label><url/path>" keeping the tail of the value visible.
say_tail() {
  local label="$1" value="$2" avail
  avail=$(( $(term_width) - ${#label} ))
  [ "$avail" -lt 6 ] && avail=6
  printf '%s%s\n' "$label" "$(fit_tail "$value" "$avail")"
}

# collapse $HOME to ~ in a path.
tildepath() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *)         printf '%s' "$1" ;;
  esac
}

render_list() {
  local w; w="$(term_width)"
  if [ "${#URLS[@]}" -eq 0 ]; then
    say "  (no links yet — type a topic or URL, then Enter)"
    return
  fi
  say "  active links (${#URLS[@]}):"
  local i status prefix avail
  for i in "${!URLS[@]}"; do
    if kill -0 "${LPIDS[$i]}" 2>/dev/null; then status='live'; else status='DEAD'; fi
    prefix="$(printf '  [%d] %-4s ' "$((i + 1))" "$status")"
    avail=$(( w - ${#prefix} ))
    [ "$avail" -lt 6 ] && avail=6
    printf '%s%s\n' "$prefix" "$(fit_tail "${URLS[$i]}" "$avail")"
  done
}

# ---------------------------------------------------------------------------
# listener lifecycle
# ---------------------------------------------------------------------------

add_listener() {
  local url i lpid pgid
  url="$(normalize_url "$1")"

  for i in "${!URLS[@]}"; do
    if [ "${URLS[$i]}" = "$url" ]; then
      say_tail '  already listening: ' "$url"
      render_list
      return
    fi
  done

  # Spawn `ntfy sub | parse_stream` as a background job in its OWN process
  # group (set -m) so we can later kill the whole group (ntfy + parser) with a
  # single signal. ntfy's own stderr goes to the log; the shell's job-start
  # message is swallowed by the block-level 2>/dev/null.
  { set -m; ntfy sub "$url" 2>>"$LOG" | parse_stream & set +m; } 2>/dev/null
  lpid=$!
  pgid="$(ps -o pgid= -p "$lpid" 2>/dev/null | tr -d ' ')"
  [ -n "$pgid" ] || pgid="$lpid"
  disown 2>/dev/null

  URLS+=("$url")
  LPIDS+=("$lpid")
  PGIDS+=("$pgid")

  say_tail '  + listening: ' "$url"
  render_list
}

remove_listener() {
  local n idx i
  n="$(trim "$1")"
  case "$n" in
    ''|*[!0-9]*) printf '  usage: rm <number-from-the-list>\n'; return ;;
  esac
  idx=$((n - 1))
  if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#URLS[@]}" ]; then
    printf '  no link #%s\n' "$n"; return
  fi

  kill -TERM "-${PGIDS[$idx]}" 2>/dev/null
  say_tail '  - removed: ' "${URLS[$idx]}"

  local nu=() nl=() np=()
  for i in "${!URLS[@]}"; do
    [ "$i" -eq "$idx" ] && continue
    nu+=("${URLS[$i]}"); nl+=("${LPIDS[$i]}"); np+=("${PGIDS[$i]}")
  done
  URLS=("${nu[@]}"); LPIDS=("${nl[@]}"); PGIDS=("${np[@]}")
  render_list
}

shutdown() {
  [ -n "$_SHUTDOWN_DONE" ] && return
  _SHUTDOWN_DONE=1
  local i
  for i in "${!PGIDS[@]}"; do kill -TERM "-${PGIDS[$i]}" 2>/dev/null; done
  for i in "${!PGIDS[@]}"; do kill -KILL "-${PGIDS[$i]}" 2>/dev/null; done
  rm -f "$LOG" 2>/dev/null
  printf '\nStopped %d listener(s). Bye.\n' "${#PGIDS[@]}"
}

# ---------------------------------------------------------------------------
# configured-topic auto-load
#
# The notify plugin's sender stores its topic at <plugin>/.config/topic, and
# this script ships in <plugin>/desktop/, so when run in place that same file
# sits at ../.config/topic relative to the script — findable from any $PWD.
# Resolution order mirrors the sender: $NTFY_TOPIC, $NTFY_TOPIC_FILE, then the
# relative file. A copy outside the plugin folder has no plugin root above it,
# so nothing is found and nothing is auto-added.
# ---------------------------------------------------------------------------

script_dir() {
  # Directory of the real script file, following symlinks (e.g. a PATH
  # symlink to a copy), so ../.config resolves from the actual file.
  local src="${BASH_SOURCE[0]:-$0}" dir tgt
  while [ -L "$src" ]; do
    dir="$(cd -- "$(dirname -- "$src")" 2>/dev/null && pwd)" || break
    tgt="$(readlink "$src" 2>/dev/null)"
    [ -n "$tgt" ] || break
    case "$tgt" in /*) src="$tgt" ;; *) src="$dir/$tgt" ;; esac
  done
  cd -- "$(dirname -- "$src")" 2>/dev/null && pwd
}

auto_add_configured() {
  local topic file dir
  if [ -n "${NTFY_TOPIC:-}" ]; then
    topic="$(trim "$NTFY_TOPIC")"
    case "$topic" in ''|"$PLACEHOLDER") return 0 ;; esac
    say '  + topic from $NTFY_TOPIC'
    add_listener "$topic"
    return 0
  fi
  file="${NTFY_TOPIC_FILE:-$(script_dir)/../.config/topic}"
  [ -f "$file" ] || return 0
  topic="$(tr -d ' \t\r\n' < "$file" 2>/dev/null)"
  case "$topic" in ''|"$PLACEHOLDER") return 0 ;; esac
  # Accept only what the sender can have written (or a full URL) — refuse to
  # subscribe to garbage if some unrelated file happens to match the path.
  printf '%s' "$topic" | grep -qE '^([A-Za-z0-9_-]{1,64}|https?://[^[:space:]]+)$' || return 0
  dir="$(cd -- "$(dirname -- "$file")" 2>/dev/null && pwd)" && file="$dir/$(basename -- "$file")"
  say_tail '  + topic from config: ' "$(tildepath "$file")"
  add_listener "$topic"
}

# ---------------------------------------------------------------------------
# ui
# ---------------------------------------------------------------------------

require_deps() {
  local missing=() m
  command -v ntfy >/dev/null 2>&1 || missing+=("ntfy  (brew install ntfy)")
  command -v jq   >/dev/null 2>&1 || missing+=("jq    (brew install jq)")
  if ! command -v terminal-notifier >/dev/null 2>&1 && ! command -v osascript >/dev/null 2>&1; then
    missing+=("terminal-notifier or osascript")
  fi
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'claude-code-ntfy: missing dependencies:\n' >&2
    for m in "${missing[@]}"; do printf '  - %s\n' "$m" >&2; done
    exit 1
  fi
}

print_banner() {
  hr
  say ' claude-code-ntfy'
  say ' ntfy → native macOS notifications'
  hr
  print_help
  if ! command -v terminal-notifier >/dev/null 2>&1; then
    say ' note: via osascript — if silent, enable Script'
    say '       Editor in Settings ▸ Notifications'
  fi
  say_tail ' logs: ' "$(tildepath "$LOG")"
  hr
}

print_help() {
  say ' commands:'
  say '   <topic|url>   add a listener (bare ⇒ ntfy.sh)'
  say '   list          show active links'
  say '   rm <n>        stop & remove link n'
  say '   help          show these commands'
  say '   quit          stop all & exit (Ctrl-C / Ctrl-D)'
}

repl() {
  local line
  while true; do
    printf '\nntfy> '
    if ! IFS= read -r line; then
      printf '\n'; break              # Ctrl-D / EOF
    fi
    line="$(trim "$line")"
    case "$line" in
      '')            render_list ;;
      q|quit|exit)   break ;;
      h|help|'?')    print_help ;;
      l|ls|list)     render_list ;;
      rm\ *|remove\ *) remove_listener "${line#* }" ;;
      *)             add_listener "$line" ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
  --parse)    parse_stream; exit $? ;;
  -h|--help)
    _w="$(tput cols 2>/dev/null)"; case "$_w" in ''|*[!0-9]*) _w=80 ;; esac
    [ "$_w" -gt 100 ] && _w=100
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0" | fold -s -w "$_w"
    exit 0 ;;
esac

trap 'shutdown; exit 0' INT TERM
trap 'shutdown' EXIT

require_deps
print_banner
auto_add_configured
for a in "$@"; do
  [ -n "$a" ] && add_listener "$a"
done
repl
