#!/bin/zsh

# Read-only macOS junk/candidate cleanup scanner.
# It never deletes, moves, or modifies files. It only measures paths and writes reports.

set -u
setopt NULL_GLOB
setopt EXTENDED_GLOB
setopt TYPESET_SILENT

SCRIPT_DIR="${0:A:h}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="${SCRIPT_DIR}/reports/mac-junk-${TIMESTAMP}"
SUMMARY_RAW="${REPORT_DIR}/summary.raw.tsv"
SUMMARY_TSV="${REPORT_DIR}/summary.tsv"
LARGE_RAW="${REPORT_DIR}/large-files.raw.tsv"
LARGE_TSV="${REPORT_DIR}/large-files.tsv"
NOTES_TXT="${REPORT_DIR}/notes.txt"

INCLUDE_SYSTEM=1
SCAN_LARGE_FILES=1
MIN_LARGE_MB=500
DAYS_OLD=30
TOP_N=40

usage() {
  cat <<'EOF'
Usage: ./scan_mac_junk.zsh [options]

Read-only scanner for macOS cleanup candidates. It writes reports under ./reports/.

Options:
  --home-only              Skip /Library, /private/var, /tmp, and other system-wide paths.
  --no-large-files         Skip broad large-file searches in Downloads/Desktop/Documents.
  --min-large-mb <mb>      Minimum file size for large-file candidates. Default: 500.
  --days-old <days>        Age threshold for installer/archive candidates. Default: 30.
  --top <n>                Number of largest paths printed to terminal. Default: 40.
  -h, --help               Show this help.

Output:
  summary.tsv              Size-ranked cleanup candidate directories/files.
  large-files.tsv          Large personal files and old installers to review.
  notes.txt                Local snapshots, permission notes, and commands used.

This script does not delete anything.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home-only)
      INCLUDE_SYSTEM=0
      shift
      ;;
    --no-large-files)
      SCAN_LARGE_FILES=0
      shift
      ;;
    --min-large-mb)
      MIN_LARGE_MB="${2:-500}"
      shift 2
      ;;
    --days-old)
      DAYS_OLD="${2:-30}"
      shift 2
      ;;
    --top)
      TOP_N="${2:-40}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

mkdir -p "$REPORT_DIR"
: > "$SUMMARY_RAW"
: > "$LARGE_RAW"
: > "$NOTES_TXT"

typeset -A SEEN_CANDIDATE_PATHS

human_bytes() {
  awk -v bytes="$1" 'BEGIN {
    split("B KB MB GB TB PB", u, " ");
    n = bytes + 0;
    i = 1;
    while (n >= 1024 && i < 6) { n /= 1024; i++ }
    if (i == 1) printf "%.0f %s", n, u[i];
    else printf "%.2f %s", n, u[i];
  }'
}

path_bytes() {
  local p="$1"
  local kb
  kb="$(du -sk "$p" 2>/dev/null | awk 'NR == 1 { print $1 }')"
  if [[ -z "$kb" ]]; then
    echo ""
  else
    echo $(( kb * 1024 ))
  fi
}

write_note() {
  print -r -- "$*" >> "$NOTES_TXT"
}

add_candidate() {
  local category="$1"
  local risk="$2"
  local label="$3"
  local target_path="$4"
  local note="$5"

  [[ -e "$target_path" ]] || return 0

  local real_path="${target_path:A}"
  if [[ -n "${SEEN_CANDIDATE_PATHS[$real_path]:-}" ]]; then
    return 0
  fi
  SEEN_CANDIDATE_PATHS[$real_path]=1

  local bytes human
  bytes="$(path_bytes "$target_path")"
  if [[ -z "$bytes" ]]; then
    write_note "Permission or read issue: $target_path"
    return 0
  fi

  human="$(human_bytes "$bytes")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$bytes" "$human" "$category" "$risk" "$label" "$target_path" "$note" >> "$SUMMARY_RAW"
}

scan_glob() {
  local pattern="$1"
  local category="$2"
  local risk="$3"
  local label_prefix="$4"
  local note="$5"
  local -a matches

  matches=(${~pattern}(N))
  local p
  for p in "${matches[@]}"; do
    add_candidate "$category" "$risk" "${label_prefix}: ${p:t}" "$p" "$note"
  done
}

scan_find_large() {
  local root="$1"
  local category="$2"
  local risk="$3"
  local note="$4"

  [[ -d "$root" ]] || return 0

  local min_size="${MIN_LARGE_MB}M"
  find "$root" -xdev -type f -size +"$min_size" -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
      local bytes human mtime
      bytes="$(path_bytes "$file")"
      [[ -z "$bytes" ]] && continue
      human="$(human_bytes "$bytes")"
      mtime="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$file" 2>/dev/null || echo unknown)"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$bytes" "$human" "$category" "$risk" "$mtime" "$file" "$note" >> "$LARGE_RAW"
    done
}

scan_old_installers() {
  local root="$1"
  [[ -d "$root" ]] || return 0

  find "$root" -xdev -type f \
    \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.mpkg' -o -iname '*.zip' -o -iname '*.rar' -o -iname '*.7z' -o -iname '*.tar' -o -iname '*.tar.gz' -o -iname '*.tgz' -o -iname '*.iso' \) \
    -mtime +"$DAYS_OLD" -size +50M -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
      local bytes human mtime
      bytes="$(path_bytes "$file")"
      [[ -z "$bytes" ]] && continue
      human="$(human_bytes "$bytes")"
      mtime="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$file" 2>/dev/null || echo unknown)"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$bytes" "$human" "old-installer-archive" "review" "$mtime" "$file" \
        "Old installer/archive candidate; verify before deleting." >> "$LARGE_RAW"
    done
}

write_note "macOS cleanup candidate scan"
write_note "Started: $(date)"
write_note "Host: $(hostname)"
write_note "User: ${USER:-unknown}"
write_note "Home: ${HOME}"
write_note "This script is read-only and did not delete anything."
write_note ""

echo "Scanning common cleanup candidate locations..."

# User-level caches and logs. Most are reproducible, but deleting active app caches can sign you out or slow first launch.
scan_glob "${HOME}/Library/Caches/*" "user-cache" "usually-safe" "User cache" "App cache. Quit related apps before deleting."
scan_glob "${HOME}/Library/Logs/*" "user-log" "usually-safe" "User log" "Diagnostic logs. Useful only for troubleshooting."
scan_glob "${HOME}/Library/Saved Application State/*" "saved-state" "usually-safe" "Saved app state" "Window/session restore state."
scan_glob "${HOME}/Library/Application Support/CrashReporter/*" "crash-report" "usually-safe" "Crash report" "Old crash reports."
scan_glob "${HOME}/Library/Containers/*/Data/Library/Caches" "container-cache" "usually-safe" "Sandbox cache" "Sandboxed app cache."
scan_glob "${HOME}/Library/Group Containers/*/Library/Caches" "group-container-cache" "usually-safe" "Group cache" "Shared app-group cache."
add_candidate "trash" "review" "User Trash" "${HOME}/.Trash" "Review before emptying."
add_candidate "user-cache" "usually-safe" "Unix user cache" "${HOME}/.cache" "CLI and developer tool cache."

# Developer/tool caches. These are often large and reproducible, but can cost time to rebuild.
add_candidate "xcode" "usually-safe" "Xcode DerivedData" "${HOME}/Library/Developer/Xcode/DerivedData" "Build products and indexes; Xcode rebuilds them."
add_candidate "xcode" "review" "Xcode Archives" "${HOME}/Library/Developer/Xcode/Archives" "Signed app archives. Keep anything you may need for releases."
add_candidate "xcode" "usually-safe" "Xcode iOS DeviceSupport" "${HOME}/Library/Developer/Xcode/iOS DeviceSupport" "Device symbols. Xcode can re-download/recreate."
add_candidate "xcode" "usually-safe" "Xcode Previews" "${HOME}/Library/Developer/Xcode/UserData/Previews" "SwiftUI preview simulator data."
add_candidate "simulator" "review" "CoreSimulator devices" "${HOME}/Library/Developer/CoreSimulator/Devices" "Simulator apps/data. Deleting removes simulator state."
add_candidate "simulator" "usually-safe" "CoreSimulator caches" "${HOME}/Library/Developer/CoreSimulator/Caches" "Simulator cache."
add_candidate "homebrew" "usually-safe" "Homebrew cache" "${HOME}/Library/Caches/Homebrew" "Downloaded formula bottles and source caches."
add_candidate "node" "usually-safe" "npm cache" "${HOME}/.npm/_cacache" "npm package cache."
add_candidate "node" "usually-safe" "Yarn cache" "${HOME}/Library/Caches/Yarn" "Yarn package cache."
add_candidate "node" "usually-safe" "pnpm store" "${HOME}/Library/pnpm/store" "pnpm content-addressed package store."
add_candidate "node" "usually-safe" "pnpm store legacy" "${HOME}/.pnpm-store" "Legacy pnpm package store."
add_candidate "python" "usually-safe" "pip cache" "${HOME}/Library/Caches/pip" "Python package download/build cache."
add_candidate "ruby" "usually-safe" "Bundler cache" "${HOME}/.bundle/cache" "Ruby bundler cache."
add_candidate "gradle" "usually-safe" "Gradle caches" "${HOME}/.gradle/caches" "Gradle dependency/build cache."
add_candidate "cargo" "usually-safe" "Cargo registry cache" "${HOME}/.cargo/registry/cache" "Rust crate download cache."
add_candidate "go" "usually-safe" "Go build cache" "${HOME}/Library/Caches/go-build" "Go compiler build cache."

# Large application support areas that are not junk by default, but often explain disk usage.
add_candidate "backup" "review" "iPhone/iPad backups" "${HOME}/Library/Application Support/MobileSync/Backup" "Personal device backups. Verify in Finder before deleting."
add_candidate "mail" "review" "Mail downloads" "${HOME}/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" "Attachments downloaded by Mail."
add_candidate "messages" "review" "Messages attachments" "${HOME}/Library/Messages/Attachments" "Personal message attachments."

if [[ "$INCLUDE_SYSTEM" -eq 1 ]]; then
  scan_glob "/Library/Caches/*" "system-cache" "usually-safe-with-admin" "System cache" "System-wide app cache; may need admin privileges to remove."
  scan_glob "/Library/Logs/*" "system-log" "usually-safe-with-admin" "System log" "System-wide logs."
  scan_glob "/private/var/folders/*/*/C" "system-temp-cache" "usually-safe-with-reboot" "var folders cache" "Per-user temporary cache. Prefer reboot before manual cleanup."
  add_candidate "temp" "usually-safe-with-reboot" "System temp" "/private/var/tmp" "Temporary files; avoid deleting active files."
  add_candidate "temp" "usually-safe-with-reboot" "tmp" "/tmp" "Temporary files; avoid deleting active files."
  add_candidate "system-log" "usually-safe-with-admin" "var log" "/var/log" "System logs."
fi

if command -v brew >/dev/null 2>&1; then
  brew_cache="$(brew --cache 2>/dev/null || true)"
  if [[ -n "${brew_cache:-}" ]]; then
    add_candidate "homebrew" "usually-safe" "Homebrew cache from brew --cache" "$brew_cache" "Downloaded Homebrew bottles and sources."
  fi
fi

if command -v tmutil >/dev/null 2>&1; then
  write_note ""
  write_note "Local Time Machine snapshots:"
  tmutil listlocalsnapshots / >> "$NOTES_TXT" 2>&1 || write_note "Could not list local snapshots."
fi

if [[ "$SCAN_LARGE_FILES" -eq 1 ]]; then
  echo "Scanning large files and old installers for review..."
  scan_find_large "${HOME}/Downloads" "large-file" "review" "Large file in Downloads."
  scan_find_large "${HOME}/Desktop" "large-file" "review" "Large file on Desktop."
  scan_find_large "${HOME}/Documents" "large-file" "review" "Large file in Documents."
  scan_old_installers "${HOME}/Downloads"
  scan_old_installers "${HOME}/Desktop"
fi

{
  printf 'bytes\thuman\tcategory\trisk\tlabel\tpath\tnote\n'
  sort -nr "$SUMMARY_RAW"
} > "$SUMMARY_TSV"

{
  printf 'bytes\thuman\tcategory\trisk\tmodified\tpath\tnote\n'
  sort -nr "$LARGE_RAW"
} > "$LARGE_TSV"

write_note ""
write_note "Finished: $(date)"
write_note "Reports:"
write_note "  $SUMMARY_TSV"
write_note "  $LARGE_TSV"
write_note "  $NOTES_TXT"

echo ""
echo "Largest cleanup candidates:"
awk -F '\t' 'NR > 1 { printf "%12s  %-26s  %-12s  %s\n", $2, $3, $4, $6 }' "$SUMMARY_TSV" | head -n "$TOP_N"

echo ""
echo "Reports written to:"
echo "  $REPORT_DIR"
echo ""
echo "No files were deleted."
