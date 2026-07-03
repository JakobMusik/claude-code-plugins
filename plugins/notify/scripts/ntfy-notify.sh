#!/usr/bin/env bash
# ntfy-notify.sh — push Claude Code hook events to ntfy.sh as phone notifications.
#
# Bundled with the `notify` plugin. The plugin's hooks/hooks.json invokes this
# (via ${CLAUDE_PLUGIN_ROOT}) on three session events:
#     stop                Claude finished its turn and is awaiting you        (Stop)
#     askuserquestion     Claude is asking you a multiple-choice question     (PreToolUse: AskUserQuestion)
#     permission_request  Claude is blocked, needing you to approve a tool    (PermissionRequest)
#
# For a session event the notification is composed from the transcript as:
#     Title:  "<session name>@<cwd>" — the /rename title if set, else the
#             auto-generated summary title, joined with the working-dir basename.
#     Body:   the first few lines of Claude's latest reply (the last assistant
#             message's text), or the title if that turn carried no prose.
# Which event fired is still encoded by the Tags (emoji) and Priority. Reads the
# hook JSON on stdin.
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
# each kind). Order matters because the transcript writes an agent-name record
# right AFTER a custom-title, so a naive "last record" pick would clobber the
# user's /rename with a stale auto name. May be empty (brand-new session); the
# caller then falls back to the cwd basename.
session_title() {  # session_title <transcript>
    [ -n "${1:-}" ] && [ -f "$1" ] || return 0
    jq -rn '
        reduce inputs as $r ({};
          if   $r.type=="custom-title" and (($r.customTitle // "") != "") then .c = $r.customTitle
          elif $r.type=="ai-title"     and (($r.aiTitle    // "") != "") then .a = $r.aiTitle
          elif $r.type=="agent-name"   and (($r.agentName  // "") != "") then .g = $r.agentName
          else . end)
        | .c // .a // .g // empty' "$1" 2>/dev/null
}

# Body: the first few lines of Claude's most recent reply — the text blocks of
# the last assistant message (thinking / tool_use blocks are skipped). Empty when
# the latest turns carried no prose (e.g. a bare tool call); the caller then falls
# back to the title so the notification is never blank.
REPLY_MAX_LINES=4
REPLY_MAX_CHARS=500
latest_reply() {  # latest_reply <transcript>
    local text
    [ -n "${1:-}" ] && [ -f "$1" ] || return 0
    text="$(jq -rn '
        [ inputs
          | select(.type=="assistant" and .message.role=="assistant")
          | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
          | select(. != null and (gsub("\\s"; "") | length > 0))
        ] | last // ""' "$1" 2>/dev/null)"
    [ -n "$text" ] || return 0
    printf '%s' "$text" | awk -v m="$REPLY_MAX_LINES" -v c="$REPLY_MAX_CHARS" '
        NF { line[++n] = $0 } n >= m { exit }
        END {
            body = ""
            for (i = 1; i <= n; i++) body = body (i > 1 ? "\n" : "") line[i]
            if (length(body) > c) body = substr(body, 1, c) "\342\200\246"   # ellipsis
            printf "%s", body
        }'
}

# Read the hook JSON once, compose "<name>@<cwd>" for the title and the latest
# reply for the body, and fire. Priority + emoji tags (args) still mark the event.
notify_event() {  # notify_event <priority> <tags>
    local input="" transcript cwd base name title body
    [ -t 0 ] || input="$(cat)"
    transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
    [ -n "$cwd" ] || cwd="$PWD"
    base="$(basename "$cwd" 2>/dev/null)"; case "$base" in "/"|".") base="" ;; esac
    name="$(session_title "$transcript")"
    if   [ -n "$name" ] && [ -n "$base" ]; then title="${name}@${base}"
    elif [ -n "$name" ];                   then title="$name"
    elif [ -n "$base" ];                   then title="$base"
    else                                        title="claude session"
    fi
    title="$(printf '%s' "$title" | tr -d '\r\n')"   # Title is an HTTP header: single line
    body="$(latest_reply "$transcript")"
    [ -n "$body" ] || body="$title"
    post_bg "$title" "$1" "$2" "$body"
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
    stop)               notify_event "high" "white_check_mark" ;;
    askuserquestion)    notify_event "max"  "question" ;;
    permission_request) notify_event "max"  "lock" ;;
    "")
        echo "usage: ntfy-notify.sh {stop|askuserquestion|permission_request|set-topic|show-topic|test}" >&2
        exit 2
        ;;
    *) notify_event "default" "information_source" ;;
esac
