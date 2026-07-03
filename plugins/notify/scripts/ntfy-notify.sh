#!/usr/bin/env bash
# ntfy-notify.sh — push Claude Code hook events to ntfy.sh as phone notifications.
#
# Bundled with the `notify` plugin. The plugin's hooks/hooks.json invokes this
# (via ${CLAUDE_PLUGIN_ROOT}) on three session events:
#     stop                Claude finished its turn and is awaiting you        (Stop)
#     askuserquestion     Claude is asking you a multiple-choice question     (PreToolUse: AskUserQuestion)
#     permission_request  Claude is blocked, needing you to approve a tool    (PermissionRequest)
#
# The notification BODY is the SESSION NAME (the title from /rename, shown in the
# session list, e.g. "notify-skill-creation"). Which event fired is conveyed by the
# ntfy Title, Tags (emoji) and Priority — not the body. Reads the hook JSON on stdin.
#
# Config subcommands (used by SKILL.md setup, not by the hooks):
#     set-topic [TOPIC]   write the private ntfy topic (generates a random one if omitted)
#     show-topic          print the configured topic and its subscribe URL
#     test                send a test notification to confirm wiring
#
# Topic resolution (first hit wins):
#     1. $NTFY_TOPIC
#     2. $NTFY_TOPIC_FILE       (path override, if set)
#     3. ${XDG_CONFIG_HOME:-~/.config}/claude-code-notify/topic   (written by `set-topic`)
# The topic lives in a stable user-config path (NOT inside the plugin dir) so it is
# identical whether the script runs as a hook or a plain command, and survives plugin
# updates/reinstalls. ntfy topics are world-readable, so the topic name is the ONLY
# privacy boundary: there is no shared default and the script refuses to POST without one.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEFAULT_TOPIC_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-code-notify/topic"
TOPIC_FILE="${NTFY_TOPIC_FILE:-$DEFAULT_TOPIC_FILE}"
PLACEHOLDER="REPLACE_ME_WITH_A_PRIVATE_NTFY_TOPIC"

read_topic() {
    if [ -n "${NTFY_TOPIC:-}" ]; then printf '%s' "$NTFY_TOPIC"; return 0; fi
    if [ -f "$TOPIC_FILE" ]; then tr -d ' \t\r\n' < "$TOPIC_FILE" 2>/dev/null; fi
}

gen_topic() {
    local rand
    rand="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 12)"
    [ -n "$rand" ] || return 1
    printf 'claude-code-%s' "$rand"
}

# Fire the notification and return immediately: the curl is detached in a
# subshell so a slow/failed network never delays Claude's turn. Bounded timeouts
# are a backstop. Silent no-op when no real topic is configured.
post_bg() {  # post_bg <title> <priority> <tags> <body>
    local topic; topic="$(read_topic)"
    case "$topic" in ""|"$PLACEHOLDER") return 0 ;; esac
    ( printf '%s' "$4" | curl -fsS -X POST "https://ntfy.sh/${topic}" \
        -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
        --data-binary @- --connect-timeout 3 --max-time 8 >/dev/null 2>&1 & ) &
}

# The session's display name is NOT in the hook payload; it lives in the
# transcript, which records three kinds of title over the session's life:
#     custom-title  .customTitle  what the user set with /rename
#     ai-title      .aiTitle      the auto-generated summary shown in the list
#     agent-name    .agentName    the early auto name, before an ai-title exists
# We mirror what the session list shows by PRECEDENCE, not document order:
# a /rename wins over an ai-title wins over an agent-name (taking the last of
# each kind, so a mid-session /rename is reflected). Order matters because the
# transcript writes an agent-name right AFTER a custom-title, so a naive
# "last record" pick would clobber the user's /rename with a stale auto name.
# Falls back to the working directory's basename, then a generic label.
session_name() {
    local input="" transcript cwd name base
    [ -t 0 ] || input="$(cat)"
    transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
    [ -n "$cwd" ] || cwd="$PWD"
    name=""
    if [ -n "$transcript" ] && [ -f "$transcript" ]; then
        name="$(jq -rn '
            reduce inputs as $r ({};
              if   $r.type=="custom-title" and (($r.customTitle // "") != "") then .c = $r.customTitle
              elif $r.type=="ai-title"     and (($r.aiTitle    // "") != "") then .a = $r.aiTitle
              elif $r.type=="agent-name"   and (($r.agentName  // "") != "") then .g = $r.agentName
              else . end)
            | .c // .a // .g // empty' \
                "$transcript" 2>/dev/null)"
    fi
    if [ -z "$name" ]; then
        base="$(basename "$cwd" 2>/dev/null)"
        case "$base" in ""|"/"|".") ;; *) name="$base" ;; esac
    fi
    [ -n "$name" ] || name="claude session"
    printf '%s' "$name"
}

STAGE="${1:-}"
case "$STAGE" in
    set-topic)
        topic="${2:-}"
        [ -n "$topic" ] || topic="$(gen_topic)" || { echo "could not generate a random topic" >&2; exit 1; }
        if ! printf '%s' "$topic" | grep -qE '^[A-Za-z0-9_-]{1,64}$'; then
            echo "topic must be 1-64 chars of [A-Za-z0-9_-]" >&2; exit 1
        fi
        mkdir -p "$(dirname "$TOPIC_FILE")"
        printf '%s\n' "$topic" > "$TOPIC_FILE"
        chmod 600 "$TOPIC_FILE" 2>/dev/null || true
        printf 'ntfy topic set: %s\nSubscribe:      https://ntfy.sh/%s\n' "$topic" "$topic"
        ;;
    show-topic)
        topic="$(read_topic)"
        [ -n "$topic" ] || { echo "no ntfy topic configured (run: ntfy-notify.sh set-topic)"; exit 1; }
        printf 'topic:     %s\nsubscribe: https://ntfy.sh/%s\n' "$topic" "$topic"
        ;;
    test)
        topic="$(read_topic)"
        [ -n "$topic" ] || { echo "no ntfy topic configured (run: ntfy-notify.sh set-topic)"; exit 1; }
        printf '%s' "notify skill test" | curl -fsS -X POST "https://ntfy.sh/${topic}" \
            -H "Title: Test - notify skill" -H "Priority: high" -H "Tags: bell" \
            --data-binary @- --connect-timeout 3 --max-time 8 >/dev/null 2>&1 \
            && echo "sent test notification to https://ntfy.sh/${topic}" \
            || { echo "failed to reach https://ntfy.sh/${topic}" >&2; exit 1; }
        ;;
    stop)               post_bg "Done - awaiting you" "high" "white_check_mark" "$(session_name)" ;;
    askuserquestion)    post_bg "Question for you"    "max"  "question"          "$(session_name)" ;;
    permission_request) post_bg "Permission needed"   "max"  "lock"              "$(session_name)" ;;
    "")
        echo "usage: ntfy-notify.sh {stop|askuserquestion|permission_request|set-topic|show-topic|test}" >&2
        exit 2
        ;;
    *) post_bg "claude: $STAGE" "default" "information_source" "$(session_name)" ;;
esac
