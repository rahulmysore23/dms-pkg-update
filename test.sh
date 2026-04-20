#!/usr/bin/env bash
# test.sh — Simulates exactly what PkgUpdateWidget.qml does at runtime.
# Run this to verify the commands work before blaming the plugin.

PASS="\033[32m✔\033[0m"
FAIL="\033[31m✘\033[0m"
INFO="\033[34m→\033[0m"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  pkgUpdate plugin — local test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── DNF ──────────────────────────────────────────────────────────────────────
echo ""
echo "[ DNF ]"
echo -e "$INFO Running: dnf list --upgrades --color=never --assumeyes"
DNF_OUT=$(dnf list --upgrades --color=never --assumeyes 2>/dev/null)

if [[ -z "$DNF_OUT" ]]; then
    echo -e "$INFO No output — no DNF updates available (or dnf not found)"
    DNF_COUNT=0
else
    # Mirror the JS parser: skip header lines, keep lines with a dot in the name
    DNF_COUNT=$(echo "$DNF_OUT" | grep -v '^Last\|^Upgradable\|^Available\|^Extra' | grep '\.' | grep -v '^$' | wc -l)
    echo -e "$PASS $DNF_COUNT DNF package(s) pending:"
    echo "$DNF_OUT" | grep -v '^Last\|^Upgradable\|^Available\|^Extra' | grep '\.' | grep -v '^$' | awk '{printf "      %-45s %s\n", $1, $2}'
fi

# ── Flatpak — installed apps ──────────────────────────────────────────────────
echo ""
echo "[ Flatpak — installed apps ]"
echo -e "$INFO Running: flatpak list --app --columns=application,version"
INSTALLED_OUT=$(flatpak list --app --columns=application,version 2>/dev/null)

if [[ -z "$INSTALLED_OUT" ]]; then
    echo -e "$FAIL No output — is flatpak installed?"
    INSTALLED_COUNT=0
else
    INSTALLED_COUNT=$(echo "$INSTALLED_OUT" | grep -c .)
    echo -e "$PASS $INSTALLED_COUNT installed app(s) found"
fi

# ── Flatpak — remote updates ──────────────────────────────────────────────────
echo ""
echo "[ Flatpak — remote updates (apps only) ]"
echo -e "$INFO Running: flatpak remote-ls --updates --app --columns=application,version,origin"
echo -e "$INFO (This may take a few seconds — it contacts remote servers)"
UPDATES_OUT=$(flatpak remote-ls --updates --app --columns=application,version,origin 2>/dev/null)

if [[ -z "$UPDATES_OUT" ]]; then
    echo -e "$INFO No output — no flatpak updates available remotely"
    FLATPAK_COUNT=0
else
    echo -e "$PASS Raw update list:"
    echo "$UPDATES_OUT" | awk '{printf "      %-45s %-15s %s\n", $1, $2, $3}'

    # Mirror the JS filter: only keep apps that are actually installed
    echo ""
    echo -e "$INFO Applying installed-apps filter..."
    FLATPAK_COUNT=0
    while IFS=$'\t' read -r name version origin; do
        if echo "$INSTALLED_OUT" | grep -q "^${name}	"; then
            echo -e "  $PASS $name ($origin)"
            FLATPAK_COUNT=$((FLATPAK_COUNT + 1))
        else
            echo -e "  $FAIL FILTERED: $name (not in installed list)"
        fi
    done <<< "$UPDATES_OUT"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((DNF_COUNT + FLATPAK_COUNT))
echo "  RESULT: $DNF_COUNT DNF + $FLATPAK_COUNT Flatpak = $TOTAL total updates"
if [[ $TOTAL -gt 0 ]]; then
    echo -e "  $PASS The plugin should show $TOTAL update(s)"
else
    echo -e "  $INFO Everything is up to date (or commands returned nothing)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
