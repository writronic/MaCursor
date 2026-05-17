#!/bin/bash
set -euo pipefail

ARCH="${1:?Usage: $0 <arm64|x86_64|universal>}"

APP_NAME="MaCursor"
SCHEME="MaCursor"

SIGNING_IDENTITY="${SIGNING_IDENTITY:?Error: SIGNING_IDENTITY not set. Export it or pass via env.}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-MaCursor}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
XCODEPROJ="${PROJECT_ROOT}/MaCursor.xcodeproj"

ENTITLEMENTS_MAIN="${PROJECT_ROOT}/MaCursor/MaCursor.entitlements"
ENTITLEMENTS_HELPER="${PROJECT_ROOT}/mousecloakHelper/mousecloakHelper.entitlements"
OUTPUT_DIR="${PROJECT_ROOT}/output"

CODESIGN_EXTRA=()
if [[ -n "${CI:-}" ]]; then
    CODESIGN_EXTRA=(--keychain build.keychain)
fi

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" && "$ARCH" != "universal" ]]; then
    echo "❌ Invalid architecture: $ARCH (must be arm64, x86_64, or universal)"
    exit 1
fi

if [[ "$ARCH" == "universal" ]]; then
    DMG_NAME="MaCursor.dmg"
else
    DMG_NAME="MaCursor-${ARCH}.dmg"
fi

DMG_OUTPUT="${OUTPUT_DIR}/${DMG_NAME}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  MaCursor Build & DMG — ${ARCH}                            "
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$OUTPUT_DIR"



build_single_arch() {
    local target_arch="$1"
    local build_dir="${PROJECT_ROOT}/build_${target_arch}"
    local release_dir="${build_dir}/Build/Products/Release"

    echo "  Building ${target_arch}..."
    xcodebuild \
        -project "$XCODEPROJ" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$build_dir" \
        -arch "$target_arch" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=NO \
        clean build 2>&1 | tail -5

    if [[ ! -d "${release_dir}/${APP_NAME}.app" ]]; then
        echo "❌ Build failed for ${target_arch} — app not found at: ${release_dir}/${APP_NAME}.app"
        exit 1
    fi
}



echo "▶ Phase 1: Building ${APP_NAME} (${ARCH})..."

if [[ "$ARCH" == "universal" ]]; then
    BUILD_DIR="${PROJECT_ROOT}/build_arm64"
    RELEASE_DIR="${BUILD_DIR}/Build/Products/Release"
    APP_PATH="${RELEASE_DIR}/${APP_NAME}.app"

    build_single_arch arm64
    build_single_arch x86_64

    echo "  Merging architectures with lipo..."

    find "${APP_PATH}" -type f | while read -r filepath; do
        if file "$filepath" 2>/dev/null | grep -q "Mach-O"; then
            relative="${filepath#${RELEASE_DIR}/}"
            arm64_bin="${PROJECT_ROOT}/build_arm64/Build/Products/Release/${relative}"
            x86_bin="${PROJECT_ROOT}/build_x86_64/Build/Products/Release/${relative}"

            if [[ -f "$x86_bin" ]]; then
                arm64_archs=$(lipo -archs "$arm64_bin" 2>/dev/null || echo "")
                x86_archs=$(lipo -archs "$x86_bin" 2>/dev/null || echo "")

                if echo "$arm64_archs" | grep -q "arm64" && echo "$arm64_archs" | grep -q "x86_64"; then
                    echo "    skip (already universal): ${relative##*/}"
                elif [[ "$arm64_archs" == "$x86_archs" ]]; then
                    echo "    skip (same arch): ${relative##*/}"
                else
                    lipo -create "$arm64_bin" "$x86_bin" -output "$filepath"
                    echo "    lipo: ${relative##*/}"
                fi
            fi
        fi
    done

    echo "  Verifying universal binary..."
    lipo -info "$APP_PATH/Contents/MacOS/MaCursor"
else
    BUILD_DIR="${PROJECT_ROOT}/build_${ARCH}"
    RELEASE_DIR="${BUILD_DIR}/Build/Products/Release"
    APP_PATH="${RELEASE_DIR}/${APP_NAME}.app"

    build_single_arch "$ARCH"
fi

echo "✅ Phase 1 complete: Build succeeded."
echo ""



echo "▶ Phase 2: Re-signing with Developer ID Application..."

echo "  Signing Installer.xpc..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "${CODESIGN_EXTRA[@]}" \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"

echo "  Signing Downloader.xpc..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "${CODESIGN_EXTRA[@]}" \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"

echo "  Signing Autoupdate..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "${CODESIGN_EXTRA[@]}" \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"

echo "  Signing Updater.app..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "${CODESIGN_EXTRA[@]}" \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"

echo "  Signing Sparkle.framework..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "${CODESIGN_EXTRA[@]}" \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework"

echo "  Signing mousecloak..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "${CODESIGN_EXTRA[@]}" \
    "$APP_PATH/Contents/MacOS/mousecloak"

echo "  Signing macursorhelper..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "${CODESIGN_EXTRA[@]}" \
    --entitlements "$ENTITLEMENTS_HELPER" \
    "$APP_PATH/Contents/Library/LoginItems/com.writronic.macursorhelper.app"

echo "  Signing MaCursor.app..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "${CODESIGN_EXTRA[@]}" \
    --entitlements "$ENTITLEMENTS_MAIN" \
    "$APP_PATH"

echo "✅ Phase 2 complete: All binaries re-signed."
echo ""



echo "▶ Phase 3: Verifying signatures..."

codesign --verify --deep --strict "$APP_PATH"
echo "  ✅ codesign --verify --deep --strict: PASSED"

spctl --assess --type exec --verbose "$APP_PATH" 2>&1 || true
echo "  ✅ spctl assess complete"
echo ""



echo "▶ Phase 4: Notarizing the .app (this may take a few minutes)..."

NOTARIZE_ZIP="${BUILD_DIR}/${APP_NAME}-notarize.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

if [[ -n "${CI:-}" ]]; then
    SUBMIT_JSON=$(xcrun notarytool submit "$NOTARIZE_ZIP" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait --output-format json 2>&1)
else
    SUBMIT_JSON=$(xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait --output-format json 2>&1)
fi

APP_STATUS=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<< "$SUBMIT_JSON")
APP_SUBMIT_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "$SUBMIT_JSON")

if [[ "$APP_STATUS" != "Accepted" ]]; then
    echo "❌ App notarization failed with status: $APP_STATUS"
    if [[ -n "${CI:-}" ]]; then
        xcrun notarytool log "$APP_SUBMIT_ID" \
            --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" || true
    else
        xcrun notarytool log "$APP_SUBMIT_ID" --keychain-profile "$KEYCHAIN_PROFILE" || true
    fi
    exit 1
fi

rm -f "$NOTARIZE_ZIP"

echo "✅ Phase 4 complete: App notarization accepted."
echo ""



echo "▶ Phase 5: Stapling notarization ticket to .app..."

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "✅ Phase 5 complete: App stapled."
echo ""



echo "▶ Phase 6: Checking create-dmg..."

if ! command -v create-dmg &>/dev/null; then
    echo "  create-dmg not found. Installing..."
    npm install --global create-dmg

    (cd "$(npm root -g)/create-dmg" && npm rebuild) 2>/dev/null || true
    echo "  ✅ create-dmg installed."
elif ! create-dmg --help &>/dev/null; then
    echo "  create-dmg found but broken (likely Node.js version mismatch). Rebuilding..."
    (cd "$(npm root -g)/create-dmg" && npm rebuild)
    echo "  ✅ create-dmg rebuilt."
else
    echo "  ✅ create-dmg available."
fi
echo ""



echo "▶ Phase 7: Creating DMG with create-dmg..."

rm -f "$DMG_OUTPUT"
rm -f "${PROJECT_ROOT}/${APP_NAME} "*.dmg 2>/dev/null || true

create-dmg \
    --overwrite \
    --identity "$SIGNING_IDENTITY" \
    --dmg-title "$APP_NAME" \
    "$APP_PATH" \
    "$OUTPUT_DIR/"

CREATED_DMG=$(ls -t "${OUTPUT_DIR}/${APP_NAME} "*.dmg 2>/dev/null | head -1 || true)
if [[ -n "$CREATED_DMG" && -f "$CREATED_DMG" ]]; then
    mv "$CREATED_DMG" "$DMG_OUTPUT"
elif [[ -f "${OUTPUT_DIR}/${APP_NAME}.dmg" && "$DMG_NAME" != "${APP_NAME}.dmg" ]]; then
    mv "${OUTPUT_DIR}/${APP_NAME}.dmg" "$DMG_OUTPUT"
fi

if [[ ! -f "$DMG_OUTPUT" ]]; then
    echo "❌ DMG creation failed — output not found."
    exit 1
fi

echo "✅ Phase 7 complete: ${DMG_NAME} created."
echo ""



echo "▶ Phase 8: Verifying DMG signature..."

codesign --verify "$DMG_OUTPUT"
echo "  ✅ DMG signature verified."
echo ""



echo "▶ Phase 9: Submitting DMG for notarization (this may take a few minutes)..."

if [[ -n "${CI:-}" ]]; then
    DMG_SUBMIT_JSON=$(xcrun notarytool submit "$DMG_OUTPUT" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait --output-format json 2>&1)
else
    DMG_SUBMIT_JSON=$(xcrun notarytool submit "$DMG_OUTPUT" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait --output-format json 2>&1)
fi

DMG_STATUS=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<< "$DMG_SUBMIT_JSON")
DMG_SUBMIT_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<< "$DMG_SUBMIT_JSON")

if [[ "$DMG_STATUS" != "Accepted" ]]; then
    echo "❌ DMG notarization failed with status: $DMG_STATUS"
    if [[ -n "${CI:-}" ]]; then
        xcrun notarytool log "$DMG_SUBMIT_ID" \
            --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" || true
    else
        xcrun notarytool log "$DMG_SUBMIT_ID" --keychain-profile "$KEYCHAIN_PROFILE" || true
    fi
    exit 1
fi

echo "✅ Phase 9 complete: DMG notarization accepted."
echo ""



echo "▶ Phase 10: Stapling notarization ticket to DMG..."

xcrun stapler staple "$DMG_OUTPUT"
xcrun stapler validate "$DMG_OUTPUT"

echo "✅ Phase 10 complete: DMG stapled."
echo ""



FINAL_SIZE=$(du -h "$DMG_OUTPUT" | cut -f1)

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅ SUCCESS: ${DMG_NAME} (${FINAL_SIZE})                   "
echo "║  Location: ${DMG_OUTPUT}                                   "
echo "╚══════════════════════════════════════════════════════════════╝"
