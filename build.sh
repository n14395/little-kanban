#!/bin/bash
# Little Kanban — build, package, sign and publish.
#
#   ./build.sh                 build the production build/LittleKanban.app
#   ./build.sh --dmg           …and package it into build/LittleKanban.dmg
#   ./build.sh --sign          …Developer ID sign the .app and .dmg, notarize and staple
#   ./build.sh --publish vN.N  tag, push and cut a GitHub release from build/LittleKanban.dmg
#
# Flags combine — `./build.sh --sign --publish v1.2` signs, notarizes and releases in
# one go. `--publish` on its own does not rebuild: it requires build/LittleKanban.dmg to
# already exist.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LittleKanban"
BUILD_DIR="$PWD/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
BUNDLE_ID="com.n14395.LittleKanban"

# Exported from ~/.zshrc. The literal fallback keeps the script working when it is
# run from a shell that never sourced it (cron, a GUI runner, `env -i`).
DEV_TEAM_IDENTITY="${DEV_TEAM_IDENTITY:-Developer ID Application: Nicholas Fay (P52946XHRJ)}"
NOTARY_PROFILE="notary-profile"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

WANT_DMG=0
WANT_SIGN=0
PUBLISH_VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)   WANT_DMG=1 ;;
        --sign)  WANT_SIGN=1 ;;
        --publish)
            [[ $# -ge 2 ]] || die "--publish needs a version argument, e.g. --publish v1.2"
            PUBLISH_VERSION="$2"; shift ;;
        --publish=*) PUBLISH_VERSION="${1#*=}" ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown flag: $1 (try --help)" ;;
    esac
    shift
done

# vN.N or vN.N.N — anything else is a typo we would rather catch before tagging.
if [[ -n "$PUBLISH_VERSION" ]]; then
    [[ "$PUBLISH_VERSION" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
        || die "--publish needs a version like v1.2 or v1.2.3 (got: '$PUBLISH_VERSION')"
    VERSION_NUM="${PUBLISH_VERSION#v}"
fi

# Full Xcode, not the bare Command Line Tools: xcodebuild refuses to run under
# CLT, and even SwiftPM needs Xcode's toolchain for the SwiftUI macro plugins.
# Set DEVELOPER_DIR for this process only — the system default is left alone.
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcode-select -p 2>/dev/null | grep -q '\.app'; then
    for xc in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [[ -d "$xc" ]]; then export DEVELOPER_DIR="$xc/Contents/Developer"; break; fi
    done
fi

# xcodebuild is extremely chatty, and `xcodebuild | grep` throws away its exit
# status — which would let a failed compile fall through to packaging whatever
# stale bundle happened to be lying around. Filter the noise, keep the status.
xcb() {
    local log
    log="$(mktemp "${TMPDIR:-/tmp}/xcodebuild.XXXXXX")"
    if ! xcodebuild "$@" >"$log" 2>&1; then
        grep -E "error:|BUILD FAILED" "$log" | tail -30
        echo "xcodebuild failed — full log: $log" >&2
        return 1
    fi
    grep -E "^\*\* BUILD" "$log" || true
    rm -f "$log"
}

# A plain drag-to-install image: the app plus an /Applications symlink, nothing
# else. Staged under build/ so the volume contains exactly those two items and
# no stray DerivedData.
DMG_STAGING="$BUILD_DIR/.dmg-staging"
cleanup() { rm -rf "$DMG_STAGING"; return 0; }
trap cleanup EXIT

make_dmg() {
    [[ -d "$APP_PATH" ]] || die "$APP_PATH not found — build it first"
    step "Packaging $APP_NAME.dmg"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    # ditto, not cp: it preserves the code signature and extended attributes.
    ditto "$APP_PATH" "$DMG_STAGING/$APP_NAME.app"
    ln -s /Applications "$DMG_STAGING/Applications"
    rm -f "$DMG_PATH"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" \
        -fs HFS+ -format UDZO -ov -quiet "$DMG_PATH"
    rm -rf "$DMG_STAGING"
    echo "    $DMG_PATH"
}

# codesign never recurses into nested code, and the notary service rejects a
# bundle whose frameworks / app extensions / bundled helper binaries still carry
# an older signature. So sign inside-out, deepest path first, then the bundle
# itself. Entitlements are read back off each item and re-applied: a bare
# --force re-sign silently drops them, which would break sandboxing and TCC.
sign_one() {
    local target="$1" ent="" args=()
    ent="$(mktemp "${TMPDIR:-/tmp}/entitlements.XXXXXX")"
    if codesign -d --entitlements - --xml "$target" 2>/dev/null | grep -q '<plist'; then
        codesign -d --entitlements - --xml "$target" 2>/dev/null >"$ent"
        # get-task-allow is the debugger entitlement Xcode injects into
        # development-signed builds. The notary service rejects any binary
        # that still requests it, so drop it before re-signing.
        /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' \
            "$ent" >/dev/null 2>&1 || true
        # A Developer ID signature is a distribution signature, and the
        # environments the development build carries would point every
        # distributed copy at the development side of CloudKit: sandbox push
        # tokens that production APNs will never deliver, and the development
        # database rather than the deployed schema. Pin both to production
        # here rather than in the .entitlements file, which the Xcode build
        # needs to keep matching its Apple Development profile. Harmless while
        # the container has never been promoted — the development pin was
        # equally unauthorized — and correct on the day it is.
        if /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.aps-environment' \
            "$ent" >/dev/null 2>&1; then
            /usr/libexec/PlistBuddy -c 'Set :com.apple.developer.aps-environment production' "$ent"
        fi
        if /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-identifiers' \
            "$ent" >/dev/null 2>&1; then
            /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.icloud-container-environment' \
                "$ent" >/dev/null 2>&1 || true
            /usr/libexec/PlistBuddy \
                -c 'Add :com.apple.developer.icloud-container-environment string Production' "$ent"
        fi
        args+=(--entitlements "$ent")
    else
        rm -f "$ent"; ent=""
    fi
    codesign --force --options runtime --timestamp \
        ${args[@]+"${args[@]}"} --sign "$DEV_TEAM_IDENTITY" "$target"
    [[ -n "$ent" ]] && rm -f "$ent"
    echo "    signed ${target#$BUILD_DIR/}"
}

sign_bundle() {
    local inner
    while IFS= read -r inner; do
        sign_one "$inner"
    done < <(
        {
            find "$APP_PATH/Contents" \
                \( -name '*.framework' -o -name '*.appex' -o -name '*.xpc' \
                   -o -name '*.app' -o -name '*.bundle' -o -name '*.dylib' \
                   -o -name '*.so' \) 2>/dev/null
            # Loose Mach-O helpers: bundled CLIs in Resources, login items…
            find "$APP_PATH/Contents" -type f -perm -u+x 2>/dev/null \
                | while IFS= read -r f; do
                      file -b "$f" 2>/dev/null | grep -q 'Mach-O' && printf '%s\n' "$f"
                  done
        } | grep -v "/Contents/MacOS/[^/]*$" \
          | sort -u | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-
    )
    sign_one "$APP_PATH"
}

# The Xcode build embeds its Apple Development provisioning profile — a
# profile locked to this machine's registered devices. Under a Developer ID
# signature it authorizes nothing anywhere, and shipping it is how a release
# came to carry a device list. A Developer ID build embeds a Developer ID
# provisioning profile or none at all: pass one for the app via
# DEV_ID_PROFILE once the CloudKit container needs authorizing (that is,
# once it has been promoted to Production); until then every embedded
# development profile is stripped, and sync in the released app is
# local-only — which is what it was under the wrong profile too, minus the
# pretence.
replace_profiles() {
    local embedded
    while IFS= read -r embedded; do
        rm -f "$embedded"
        echo "    stripped ${embedded#$APP_PATH/}"
    done < <(find "$APP_PATH" -name 'embedded.provisionprofile' 2>/dev/null)
    if [[ -n "${DEV_ID_PROFILE:-}" ]]; then
        [[ -f "$DEV_ID_PROFILE" ]] || die "DEV_ID_PROFILE points at nothing: $DEV_ID_PROFILE"
        cp -f "$DEV_ID_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
        echo "    embedded $DEV_ID_PROFILE"
    else
        echo "    no DEV_ID_PROFILE set — CloudKit stays unauthorized in this release"
    fi
}

sign_and_notarize() {
    step "Developer ID signing $APP_NAME.app"
    echo "    identity: $DEV_TEAM_IDENTITY"
    replace_profiles
    sign_bundle

    make_dmg

    step "Developer ID signing $APP_NAME.dmg"
    codesign --force --timestamp --sign "$DEV_TEAM_IDENTITY" "$DMG_PATH"

    step "Verifying the .dmg signature"
    if ! codesign --verify --verbose=2 "$DMG_PATH"; then
        die "codesign --verify failed for $DMG_PATH — not submitting for notarization"
    fi

    step "Notarizing (this waits on Apple; usually a few minutes)"
    local out rc=0 status uuid
    out="$(xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || rc=$?
    printf '%s\n' "$out"
    [[ $rc -eq 0 ]] || die "notarytool submit failed (exit $rc)"

    status="$(printf '%s\n' "$out" | awk -F': *' '/^ *status:/ {print $2; exit}')"
    uuid="$(printf '%s\n' "$out"   | awk -F': *' '/^ *id:/     {print $2; exit}')"
    if [[ "$status" != "Accepted" ]]; then
        if [[ -n "$uuid" ]]; then
            step "Fetching the notarization log"
            xcrun notarytool log "$uuid" --keychain-profile "$NOTARY_PROFILE" \
                "$BUILD_DIR/notary-log.json" || true
            echo "    log written to $BUILD_DIR/notary-log.json"
        fi
        die "notarization returned status: ${status:-unknown}"
    fi

    step "Stapling the ticket"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"

    step "Gatekeeper assessment"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

    step "Notarized and stapled: $DMG_PATH"
}

publish() {
    step "Publishing $PUBLISH_VERSION"
    [[ -f "$DMG_PATH" ]] \
        || die ".dmg not found: $DMG_PATH — run ./build.sh --dmg (or --sign) first"
    # Only a signed, notarized image leaves this machine. `--dmg` alone
    # packages a development-signed app whose seal the icns rebuild has had
    # to patch up — fine to look at locally, not a thing to hand out — and a
    # release nobody can open without right-clicking past Gatekeeper is worse
    # than a release a day later.
    codesign --verify "$DMG_PATH" 2>/dev/null \
        || die "$DMG_PATH is not signed — publish with ./build.sh --sign --publish $PUBLISH_VERSION"
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "$PWD is not inside a git repository — cannot tag or release"
    command -v gh >/dev/null 2>&1 || die "the GitHub CLI (gh) is not installed"
    git remote get-url origin >/dev/null 2>&1 \
        || die "this repository has no 'origin' remote — cannot push the tag"

    local versioned="$BUILD_DIR/$APP_NAME-$VERSION_NUM.dmg"
    cp -f "$DMG_PATH" "$versioned"
    echo "    $versioned"

    git tag -a "$PUBLISH_VERSION" -m "Release $PUBLISH_VERSION"
    git push origin "$PUBLISH_VERSION"
    gh release create "$PUBLISH_VERSION" "$versioned" --verify-tag --generate-notes
}

build_app() {
    # xcodegen's source discovery is stale by default: adding or removing a
    # file here does not reach project.pbxproj until you regenerate, and the
    # symptom is a phantom "Cannot find type" for a file that is plainly there.
    #
    # **Watching project.yml alone did not catch that**, which is the whole case
    # the comment above describes: a new file under Sources/ leaves project.yml
    # untouched, so the guard said nothing and the build failed on a type that
    # was on disk. So the *directories* are watched too — a directory's mtime
    # moves when a file inside it is added, removed or renamed, and stays put
    # when one is merely edited, which is exactly the difference that matters.
    # Keying on the files themselves would rewrite the project on every save and
    # cost a full rebuild each time.
    local pbxproj="LittleKanban.xcodeproj/project.pbxproj"
    # `-nt` is true when the left file exists and the right one does not, which
    # is the fresh-clone case: LittleKanban.xcodeproj is gitignored, so there is
    # no project at all until this generates one.
    if [[ project.yml -nt $pbxproj ]] \
        || [[ -n $(find Sources Resources -type d -newer "$pbxproj" -print -quit 2>/dev/null) ]]; then
        step "Regenerating LittleKanban.xcodeproj (the file list has moved)"
        xcodegen generate
    fi

    step "Building $APP_NAME (Release)"
    local derived="$BUILD_DIR/.derived"
    # A single multiplatform target serves both macOS and iOS, so the
    # destination has to be explicit: left to itself xcodebuild is free to pick
    # an iOS simulator and we would package the wrong slice.
    xcb -project LittleKanban.xcodeproj -scheme LittleKanban \
        -configuration Release -destination 'platform=macOS' \
        -derivedDataPath "$derived" build

    rm -rf "$APP_PATH"
    # Out of DerivedData and into build/, where --dmg and --sign expect it.
    # PRODUCT_NAME and APP_NAME are both "LittleKanban" now, so this is a copy
    # rather than the rename it used to double as.
    ditto "$derived/Build/Products/Release/LittleKanban.app" "$APP_PATH"
    refresh_icns
    echo "    $APP_PATH"
}

# actool writes a truncated AppIcon.icns — ic04/ic07/ic11/ic13, nothing over
# 256px — measured on Xcode 27. Nothing on screen is soft: on macOS 26 the
# icon the system draws comes from Assets.car, which carries the full set to
# 1024. The .icns is what legacy consumers read, though, and shipping one that
# stops at 256 is an anomaly waiting for a sharp-eyed tool — so it is rebuilt
# from the catalogue's own PNGs, before signing, and the two say the same thing.
refresh_icns() {
    step "Rebuilding AppIcon.icns from the icon catalogue"
    local appiconset="Resources/Assets.xcassets/AppIcon.appiconset"
    local staging iconset size
    staging="$(mktemp -d "${TMPDIR:-/tmp}/littlekanban-icns.XXXXXX")"
    iconset="$staging/AppIcon.iconset"
    mkdir "$iconset"
    for size in 16 32 128 256 512; do
        cp "$appiconset/AppIcon-mac-${size}x${size}.png" "$iconset/icon_${size}x${size}.png"
        cp "$appiconset/AppIcon-mac-${size}x${size}@2x.png" "$iconset/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns "$iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
    rm -rf "$staging"

    # Rewriting a resource inside a signed bundle breaks its seal, and on the
    # paths that end here — no `--sign` to lay a fresh signature over the top —
    # the app would be left not matching its own manifest. Re-sign with the
    # identity the build used, read off the bundle itself, so the seal is
    # whole again and nothing else about the signature changes; ad hoc is the
    # fallback for a machine with no such identity in its keychain. `--sign`
    # runs `sign_bundle` after this and replaces the lot anyway.
    [[ $WANT_SIGN -eq 1 ]] && return 0
    local identity
    identity="$(codesign -dvv "$APP_PATH" 2>&1 \
        | awk -F= '/^Authority=/ { print $2; exit }')"
    sign_one_in_place "${identity:--}"
}

# Re-seals just the outer bundle, keeping whatever entitlements it carries —
# the inner code was not touched, so its signatures still stand.
sign_one_in_place() {
    local identity="$1" ent args=()
    ent="$(mktemp "${TMPDIR:-/tmp}/entitlements.XXXXXX")"
    if codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null | grep -q '<plist'; then
        codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null >"$ent"
        args+=(--entitlements "$ent")
    fi
    codesign --force ${args[@]+"${args[@]}"} --sign "$identity" "$APP_PATH" 2>/dev/null \
        || codesign --force ${args[@]+"${args[@]}"} --sign - "$APP_PATH"
    rm -f "$ent"
    echo "    re-sealed ${APP_PATH#$BUILD_DIR/} (icns rewrite broke the build's seal)"
}

mkdir -p "$BUILD_DIR"

if [[ $WANT_SIGN -eq 1 ]]; then
    build_app
    sign_and_notarize
elif [[ $WANT_DMG -eq 1 ]]; then
    build_app
    make_dmg
elif [[ -z "$PUBLISH_VERSION" ]]; then
    build_app
fi

if [[ -n "$PUBLISH_VERSION" ]]; then
    publish
fi

exit 0
