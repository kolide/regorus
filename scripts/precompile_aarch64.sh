#!/usr/bin/env bash
# Build the aarch64-linux shared object for regorusrb inside Docker.
# The artifact is placed at:
#   bindings/ruby/vendor/native/aarch64-linux/regorusrb.so
#
# Usage:
#   ./scripts/precompile_aarch64.sh
#   ./scripts/precompile_aarch64.sh --push
#   ./scripts/precompile_aarch64.sh --ruby 3.4.2 --rubygems 3.6.5 --bundler 2.6.5
#
# Flags:
#   --ruby <VER>        Ruby image tag (default: 3.4.2)
#   --rubygems <VER>    RubyGems version (default: 3.6.5)
#   --bundler <VER>     Bundler version (default: 2.6.5)
#   --branch <NAME>     Git branch to commit to (default: prebuilt-aarch64)
#   --no-commit         Build only; do not commit
#   --push              Push the branch after committing
#   --image <TAG>       Override Docker image (default: ruby:<RUBY>-bookworm)
#   --platform <PLAT>   Docker platform (default: linux/arm64)
#   --ext <PATH>        Extension dir (default: bindings/ruby/ext/regorusrb)
#   --out <PATH>        Output .so path (default: bindings/ruby/vendor/native/aarch64-linux/regorusrb.so)

set -Eeuo pipefail

RUBY_VER="3.4.2"
RUBYGEMS_VER="3.6.5"
BUNDLER_VER="2.6.5"
BRANCH="prebuilt-aarch64"
DO_COMMIT=1
DO_PUSH=0
PLATFORM="linux/arm64"
EXT_DIR="bindings/ruby/ext/regorusrb"
OUT_SO="bindings/ruby/vendor/native/aarch64-linux/regorusrb.so"
IMAGE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ruby) RUBY_VER="$2"; shift 2 ;;
    --rubygems) RUBYGEMS_VER="$2"; shift 2 ;;
    --bundler) BUNDLER_VER="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --no-commit) DO_COMMIT=0; shift ;;
    --push) DO_PUSH=1; shift ;;
    --image) IMAGE_OVERRIDE="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --ext) EXT_DIR="$2"; shift 2 ;;
    --out) OUT_SO="$2"; shift 2 ;;
    -h|--help) sed -n '1,120p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required." >&2; exit 1
fi
if [[ ! -d ".git" ]]; then
  echo "Run this from the root of your *regorus* working tree (a git repo)." >&2; exit 1
fi
if [[ ! -d "${EXT_DIR}" ]]; then
  echo "Extension directory not found: ${EXT_DIR}" >&2; exit 1
fi

mkdir -p "$(dirname "${OUT_SO}")"

IMAGE="${IMAGE_OVERRIDE:-ruby:${RUBY_VER}-bookworm}"
echo "==> Checking Docker image: ${IMAGE}"
if ! docker manifest inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "!! Could not find '${IMAGE}'. Falling back to ruby:${RUBY_VER}" >&2
  IMAGE="ruby:${RUBY_VER}"
fi

cat <<CFG
==> Build configuration
    Platform    : ${PLATFORM}
    Docker image: ${IMAGE}
    Ruby        : ${RUBY_VER}
    RubyGems    : ${RUBYGEMS_VER}
    Bundler     : ${BUNDLER_VER}
    Ext dir     : ${EXT_DIR}
    Output .so  : ${OUT_SO}
    Git branch  : ${BRANCH} (commit: ${DO_COMMIT}, push: ${DO_PUSH})
CFG

docker run --rm -t \
  --platform "${PLATFORM}" \
  -v "$PWD":/work -w /work \
  "${IMAGE}" bash -lc '
    set -euo pipefail

    echo "==> Installing apt dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
      build-essential pkg-config git curl ca-certificates \
      clang llvm-dev libclang-dev libssl-dev zlib1g-dev

    echo "==> Installing Rust toolchain..."
    curl -fsSL https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
    rustc --version
    cargo --version

    echo "==> Updating RubyGems to '"${RUBYGEMS_VER}"' and installing Bundler '"${BUNDLER_VER}"' ..."
    gem update --system '"${RUBYGEMS_VER}"' --no-document
    gem --version
    gem install bundler -v '"${BUNDLER_VER}"' --no-document
    bundle _'"${BUNDLER_VER}"'_ --version

    echo "==> Building the Rust extension (release)..."
    cd '"${EXT_DIR}"'
    # Force a local target directory so we know exactly where artifacts land
    export CARGO_TARGET_DIR="$PWD/target"
    # Hard clean to avoid rlib/pipelining glitches
    rm -rf "$CARGO_TARGET_DIR" || true
    CARGO_BUILD_PIPELINING=false cargo clean || true
    CARGO_BUILD_PIPELINING=false cargo build --release

    echo "==> Locating built shared object..."
    SO_CANDIDATE=$(find "$CARGO_TARGET_DIR/release" -maxdepth 1 -type f \
      \( -name "regorusrb*.so" -o -name "libregorusrb*.so" -o -name "regorusrb*.bundle" \) \
      | head -n1 || true)

    if [ -z "${SO_CANDIDATE}" ]; then
      echo "ERROR: Could not locate built shared object under $CARGO_TARGET_DIR/release" >&2
      echo "       (did the crate name change from regorusrb?)" >&2
      echo "       Contents:" >&2
      ls -la "$CARGO_TARGET_DIR/release" || true
      exit 1
    fi

    file "${SO_CANDIDATE}" || true

    echo "==> Copying artifact into bindings/ruby/vendor/native/aarch64-linux..."
    mkdir -p ../../vendor/native/aarch64-linux
    cp "${SO_CANDIDATE}" ../../vendor/native/aarch64-linux/regorusrb.so
  '

if [[ ! -f "${OUT_SO}" ]]; then
  echo "ERROR: Build did not produce ${OUT_SO}" >&2
  exit 1
fi
echo "==> Built ${OUT_SO}"

if [[ "${DO_COMMIT}" -eq 1 ]]; then
  echo "==> Committing artifact to branch ${BRANCH}..."
  if git rev-parse --verify "${BRANCH}" >/dev/null 2>&1; then
    git checkout "${BRANCH}"
  else
    git checkout -b "${BRANCH}"
  fi
  git add "${OUT_SO}"
  git commit -m "Add prebuilt aarch64-linux regorusrb.so (Ruby ${RUBY_VER}, RubyGems ${RUBYGEMS_VER}, Bundler ${BUNDLER_VER})" || true
  if [[ "${DO_PUSH}" -eq 1 ]]; then
    git push -u origin "${BRANCH}"
  fi
else
  echo "==> Skipping commit per --no-commit"
fi

echo "==> Done."
