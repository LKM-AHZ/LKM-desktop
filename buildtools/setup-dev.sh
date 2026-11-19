#!/usr/bin/env bash
#
# Phientist (理科迷) desktop development bootstrap.
#
# Checks the Flutter toolchain, resolves Dart packages and checks the platform
# build dependencies. With --install, missing Linux packages are installed via
# apt-get; Windows and macOS only print the commands to run.
#
# Usage: ./buildtools/setup-dev.sh [--install]
#
set -euo pipefail

MIN_DART="${MIN_DART:-3.13.0}"
MIN_RUST="${MIN_RUST:-1.98}"

# Concrete Debian/Ubuntu package names. `gstreamer-1.0` and `keybinder-3.0` are
# virtual names that apt resolves to unrelated packages (Qt5 GStreamer), so
# they must not be used with apt-get install.
LINUX_APT_PACKAGES=(
    ninja-build
    cmake
    clang
    pkg-config
    libgtk-3-dev
    libmpv-dev
    mpv
    libayatana-appindicator3-dev
    libkeybinder-3.0-dev
    libnotify-dev
    libsecret-1-dev
    libcurl4-openssl-dev
    libgstreamer1.0-dev
    libgstreamer-plugins-base1.0-dev
    gstreamer1.0-plugins-base
)

cd "$(dirname "$0")/.."
REQUIRED_FLUTTER="${REQUIRED_FLUTTER:-$(tr -d '\r\n' < .flutter-version)}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
error() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<'EOF'
用法: ./buildtools/setup-dev.sh [--install]
  --install  Linux 下用 apt-get 安装缺失的系统包（Windows/macOS 只提示命令）
EOF
}

INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --help|-h) usage; exit 0 ;;
        *) error "未知参数: $arg"; usage; exit 2 ;;
    esac
done

# --- Flutter toolchain -------------------------------------------------------
if ! command -v flutter >/dev/null 2>&1; then
    if [ -x "$HOME/flutter/bin/flutter" ]; then
        export PATH="$HOME/flutter/bin:$PATH"
    else
        warn "flutter not found. Install it first, for example:"
        warn "  git clone --depth 1 -b ${REQUIRED_FLUTTER} https://atomgit.com/oh-flutter/flutter_flutter.git \"\$HOME/flutter\""
        warn "  export PATH=\"\$HOME/flutter/bin:\$PATH\""
        exit 1
    fi
fi

# The patch only matches the OH-Flutter fork; a stock SDK or another platform
# should not block dependency setup (HAP builds are Linux-only).
if [ "$(uname -s)" = "Linux" ]; then
    if ! bash buildtools/patch-ohos-sdk.sh; then
        warn "OH-Flutter SDK patch not applied; HarmonyOS HAP builds need the SDK pinned in .flutter-version."
    fi
fi

log "Flutter $(flutter --version 2>/dev/null | head -n 1)"
log "Expected OH-Flutter ${REQUIRED_FLUTTER} (pubspec.lock pins Dart >= ${MIN_DART})"

# --- Dart/Flutter packages ---------------------------------------------------
log "Resolving packages (flutter pub get)"
flutter pub get

# --- Platform dependencies ---------------------------------------------------
# super_native_extensions compiles its Rust crate with cargokit during every
# native app build, so rustup is required on all desktop platforms.
check_rust() {
    if command -v rustup >/dev/null 2>&1; then
        log "Rust toolchain present"
    else
        warn "Rust toolchain not found; super_native_extensions compiles Rust during the app build."
        warn "Install it with: https://rustup.rs"
        warn "  Windows: winget install Rustlang.Rustup"
    fi
}

check_linux() {
    if ! command -v dpkg >/dev/null 2>&1; then
        warn "Non-Debian Linux: install GTK3, mpv, libayatana-appindicator3, libkeybinder-3.0, libnotify, GStreamer and libcurl with your package manager."
        check_rust
        return
    fi

    local missing=()
    local pkg
    for pkg in "${LINUX_APT_PACKAGES[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        log "Linux build dependencies present"
    elif [ "$INSTALL" = true ]; then
        log "Installing missing Linux packages: ${missing[*]}"
        sudo apt-get update -y
        sudo apt-get install -y "${missing[@]}"
    else
        warn "Missing Linux build dependencies: ${missing[*]}"
        warn "Install them with:"
        warn "  sudo apt-get install -y ${missing[*]}"
        warn "Or rerun: ./buildtools/setup-dev.sh --install"
    fi

    check_rust
}

check_macos() {
    check_rust
    if ! command -v rustc >/dev/null 2>&1; then
        return
    fi
    local ver
    ver="$(rustc --version | awk '{print $2}')"
    if awk -v v="$ver" -v min="$MIN_RUST" 'BEGIN {
        split(v, p, "."); split(min, m, ".");
        exit !(p[1] > m[1] || (p[1] == m[1] && p[2] >= m[2]))
    }'; then
        log "Rust ${ver} present"
    else
        warn "rustc ${ver} is older than stable ${MIN_RUST}; Xcode archive builds fail with E0463."
        warn "Run: rustup update stable"
    fi
}

check_windows() {
    check_rust
}

case "$(uname -s)" in
    Linux) check_linux ;;
    Darwin) check_macos ;;
    MINGW*|MSYS*|CYGWIN*) check_windows ;;
    *) warn "Unknown platform: system dependencies not checked." ;;
esac

if command -v node >/dev/null 2>&1 && command -v pnpm >/dev/null 2>&1; then
    log "Installing webf tools and building mini app assets"
    pnpm --dir webf install --frozen-lockfile --ignore-scripts
    pnpm --dir webf build
else
    warn "Node.js 24+ / pnpm not found; run before flutter run:"
    warn "  pnpm --dir webf install --frozen-lockfile && pnpm --dir webf build"
fi

log "Done. Next: flutter run (or flutter build <platform>)"
