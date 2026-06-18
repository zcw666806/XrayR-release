#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/build-release-assets.sh [source-dir] [output-dir]

Build the Linux XrayR release ZIP files expected by install.sh.

Arguments:
  source-dir  XrayR source checkout containing go.mod (default: ../XrayR)
  output-dir  Directory for generated ZIP files (default: ./dist)

Environment:
  TARGETS     Space-separated targets in GOARCH:ASSET_SUFFIX form.
              Default: amd64:64 arm64:arm64-v8a s390x:s390x
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
fi

source_dir=${1:-../XrayR}
output_dir=${2:-./dist}
targets=${TARGETS:-"amd64:64 arm64:arm64-v8a s390x:s390x"}

if [[ ! -f "${source_dir}/go.mod" ]]; then
    echo "错误：${source_dir} 中不存在 go.mod，请传入 XrayR 源码目录。" >&2
    exit 1
fi

if ! command -v go >/dev/null 2>&1; then
    echo "错误：未找到 go 命令。" >&2
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    echo "错误：未找到 zip 命令。" >&2
    exit 1
fi

source_dir=$(cd "${source_dir}" && pwd)
mkdir -p "${output_dir}"
output_dir=$(cd "${output_dir}" && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT

(
    cd "${source_dir}"
    go mod download
)

for target in ${targets}; do
    goarch=${target%%:*}
    asset_suffix=${target#*:}
    target_dir="${work_dir}/${asset_suffix}"
    asset_path="${output_dir}/XrayR-linux-${asset_suffix}.zip"

    mkdir -p "${target_dir}"
    echo "构建 linux/${goarch} -> ${asset_path}"
    (
        cd "${source_dir}"
        CGO_ENABLED=0 GOOS=linux GOARCH="${goarch}" \
            go build -trimpath -ldflags "-s -w -buildid=" -o "${target_dir}/XrayR" .
    )
    chmod +x "${target_dir}/XrayR"
    rm -f "${asset_path}"
    (
        cd "${target_dir}"
        zip -9q "${asset_path}" XrayR
    )
    (
        cd "${output_dir}"
        sha256sum "$(basename "${asset_path}")" > "$(basename "${asset_path}").sha256"
    )
done

echo "Release 资产已生成："
find "${output_dir}" -maxdepth 1 -type f -printf '%f\n' | sort
