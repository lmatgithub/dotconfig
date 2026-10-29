#!/bin/bash
# Combined Claude Code status line:
#   1. project/cwd badge (project root name:branch)
#   2. usage badge (rate-limit % when available)
#   3. model / effort badge (plus rock icon when caveman mode is on)
#
# Configured via ~/.claude/settings.json -> statusLine.command

CAVEMAN_SCRIPT="$HOME/.claude/plugins/marketplaces/caveman/src/hooks/caveman-statusline.sh"

INPUT=$(cat)

# --- caveman detection: delegate the on/off + mode detection to the
# plugin's own script (it owns the session-flag security logic), but ignore
# its text output -- we only care whether it rendered *something*, which
# feeds a rock icon into the model badge below.
CAVEMAN_RAW=""
if [ -x "$CAVEMAN_SCRIPT" ] || [ -f "$CAVEMAN_SCRIPT" ]; then
  CAVEMAN_RAW=$(printf '%s' "$INPUT" | bash "$CAVEMAN_SCRIPT" 2>/dev/null)
fi

# --- usage badge: 5-hour rate-limit usage, dimmed ---
jqget() {
  printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cur = d
for key in '$1'.split('.'):
    if not isinstance(cur, dict) or key not in cur:
        sys.exit(0)
    cur = cur[key]
if cur is not None:
    print(cur)
"
}

FIVE_HOUR_USED=$(jqget 'rate_limits.five_hour.used_percentage')
FIVE_HOUR_RESETS_AT=$(jqget 'rate_limits.five_hour.resets_at')

USAGE_PARTS=""
[ -n "$FIVE_HOUR_USED" ] && USAGE_PARTS="$(printf '%.0f' "$FIVE_HOUR_USED")%"

# Append the reset time (e.g. "8:40pm") when we know when the 5-hour window
# refreshes, so the badge reads "[34% 8:40pm]".
if [ -n "$USAGE_PARTS" ] && [ -n "$FIVE_HOUR_RESETS_AT" ]; then
  RESET_TIME=$(date -d "@$FIVE_HOUR_RESETS_AT" '+%-I:%M%P' 2>/dev/null || date -r "$FIVE_HOUR_RESETS_AT" '+%-I:%M%P' 2>/dev/null)
  [ -n "$RESET_TIME" ] && USAGE_PARTS="$USAGE_PARTS $RESET_TIME"
fi

USAGE_BADGE=""
[ -n "$USAGE_PARTS" ] && USAGE_BADGE=$(printf '\033[2;38;5;244m[%s]\033[0m' "$USAGE_PARTS")

# --- model / effort badge, dimmed, trimmed ---
# Drop the "Claude " prefix from the display name and abbreviate the effort
# level to a single short token, e.g. "Claude Sonnet 4.5" + "high" ->
# "[Sonnet 4.5:H]" instead of "[Claude Sonnet 4.5: high]".
MODEL_NAME=$(jqget 'model.display_name')
EFFORT_LEVEL=$(jqget 'effort.level')

MODEL_SHORT="${MODEL_NAME#Claude }"

EFFORT_SHORT=""
case "$EFFORT_LEVEL" in
  low) EFFORT_SHORT="L" ;;
  medium) EFFORT_SHORT="M" ;;
  high) EFFORT_SHORT="H" ;;
  xhigh) EFFORT_SHORT="XH" ;;
  max) EFFORT_SHORT="MAX" ;;
  "") EFFORT_SHORT="" ;;
  *) EFFORT_SHORT="$EFFORT_LEVEL" ;;
esac

ROCK_PREFIX=""
[ -n "$CAVEMAN_RAW" ] && ROCK_PREFIX='\xf0\x9f\xaa\xa8 '

MODEL_BADGE=""
if [ -n "$MODEL_SHORT" ]; then
  if [ -n "$EFFORT_SHORT" ]; then
    MODEL_BADGE=$(printf "\033[2;38;5;110m[${ROCK_PREFIX}%s:%s]\033[0m" "$MODEL_SHORT" "$EFFORT_SHORT")
  else
    MODEL_BADGE=$(printf "\033[2;38;5;110m[${ROCK_PREFIX}%s]\033[0m" "$MODEL_SHORT")
  fi
fi

# --- project/cwd badge, dimmed, shown first ---
# Show the current directory as a zsh-style path (home collapsed to "~",
# e.g. "~" for /home/jnx or "~/projects/pwdr-go" for
# /home/jnx/projects/pwdr-go), with the current git branch appended, e.g.
# "~/projects/pwdr-go:new-searchbar-feature".
PROJECT_DIR=$(jqget 'workspace.project_dir')
CURRENT_DIR=$(jqget 'workspace.current_dir')
CWD_BADGE=""
BASE_DIR="${CURRENT_DIR:-$PROJECT_DIR}"
if [ -n "$BASE_DIR" ]; then
  # Collapse to the project root: for git repos (including linked worktrees
  # such as .claude/worktrees/<name>) use the main repo root, so the path stays
  # clean. The branch shown next to it carries the worktree name.
  ROOT_DIR=""
  GIT_COMMON=$(git -C "$BASE_DIR" --no-optional-locks rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$GIT_COMMON" ]; then
    case "$GIT_COMMON" in
      */.git) ROOT_DIR="${GIT_COMMON%/.git}" ;;
      *) ROOT_DIR=$(git -C "$BASE_DIR" --no-optional-locks rev-parse --show-toplevel 2>/dev/null) ;;
    esac
  fi
  BRANCH_DIR="$BASE_DIR"
  [ -n "$ROOT_DIR" ] && BASE_DIR="$ROOT_DIR"

  case "$BASE_DIR" in
    "$HOME") DISPLAY_PATH="~" ;;
    "$HOME"/*) DISPLAY_PATH="~${BASE_DIR#$HOME}" ;;
    *) DISPLAY_PATH="$BASE_DIR" ;;
  esac

  BRANCH=$(git -C "$BRANCH_DIR" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$BRANCH" = "HEAD" ] && BRANCH=""

  # --- fit to terminal width ---
  # Work out how many columns are left for "path branch" after the other
  # badges, then truncate: branch first (tail ellipsis), then path (ellipsis
  # in the middle, keeping the start and deepest directories). Drops the
  # branch if needed.
  COLS="${COLUMNS:-}"
  if [ -z "$COLS" ]; then
    COLS=$(stty size 2>/dev/null </dev/tty | awk '{print $2}')
  fi
  [ -z "$COLS" ] && COLS=$(tput cols 2>/dev/null)
  case "$COLS" in ''|*[!0-9]*) COLS=100 ;; esac
  [ "$COLS" -lt 20 ] && COLS=20

  # Visible width of the other badges: strip ANSI, count chars, +1 per
  # double-width emoji (rock, bot, lightning), +1 for each joining space.
  OTHER_W=0
  if [ -n "$USAGE_BADGE" ]; then
    W=$(printf '%s' "$USAGE_BADGE" | sed 's/\x1b\[[0-9;]*m//g')
    OTHER_W=$((OTHER_W + ${#W} + 1))
  fi
  if [ -n "$MODEL_BADGE" ]; then
    W=$(printf '%s' "$MODEL_BADGE" | sed 's/\x1b\[[0-9;]*m//g')
    EXTRA=0
    [ -n "$CAVEMAN_RAW" ] && EXTRA=1
    OTHER_W=$((OTHER_W + ${#W} + EXTRA + 1))
  fi
  MARGIN=4   # Claude Code's own padding / safety slack
  AVAIL=$((COLS - OTHER_W - MARGIN))
  [ "$AVAIL" -lt 12 ] && AVAIL=12

  trunc_end() {   # keep first N-1 chars + ellipsis
    local s="$1" n="$2"
    if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:$((n - 1))}"; else printf '%s' "$s"; fi
  }
  trunc_head() {  # cut the middle: keep start + ellipsis + end, total N chars
    local s="$1" n="$2"
    if [ "${#s}" -gt "$n" ]; then
      local keep=$((n - 1))
      if [ "$keep" -lt 3 ]; then printf '…%s' "${s: -$keep}"; return; fi
      local h=$((keep / 3)) t=$((keep - keep / 3))
      printf '%s…%s' "${s:0:$h}" "${s: -$t}"
    else
      printf '%s' "$s"
    fi
  }

  PLEN=${#DISPLAY_PATH}
  if [ -n "$BRANCH" ]; then
    BLEN=${#BRANCH}
    if [ $((PLEN + 3 + BLEN)) -gt "$AVAIL" ]; then
      BMAX=$((AVAIL - 3 - PLEN))
      if [ "$BMAX" -ge 10 ]; then
        BRANCH=$(trunc_end "$BRANCH" "$BMAX")
      else
        PMAX=$((AVAIL - 3 - 10))
        if [ "$PMAX" -ge 8 ]; then
          BRANCH=$(trunc_end "$BRANCH" 10)
          DISPLAY_PATH=$(trunc_head "$DISPLAY_PATH" "$PMAX")
        else
          BRANCH=""
        fi
      fi
    fi
  fi
  DISPLAY_PATH=$(trunc_head "$DISPLAY_PATH" "$AVAIL")

  if [ -n "$BRANCH" ]; then
    # Path in khaki, branch in a different hue (pink) with a branch glyph and
    # a space separator instead of ":" so the two read as separate things.
    CWD_BADGE=$(printf '\033[2;38;5;144m%s\033[0m \033[2;38;5;175m\xe2\x8e\x87 %s\033[0m' "$DISPLAY_PATH" "$BRANCH")
  else
    CWD_BADGE=$(printf '\033[2;38;5;144m%s\033[0m' "$DISPLAY_PATH")
  fi
fi

# --- assemble ---
OUT=""
[ -n "$CWD_BADGE" ] && OUT="$CWD_BADGE"
[ -n "$USAGE_BADGE" ] && OUT="${OUT:+$OUT }$USAGE_BADGE"
[ -n "$MODEL_BADGE" ] && OUT="${OUT:+$OUT }$MODEL_BADGE"

printf '%s' "$OUT"
