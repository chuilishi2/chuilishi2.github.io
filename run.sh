#!/usr/bin/env bash
# ============================================================================
# 一键下载并上传到天翼云盘的脚本
# 获取方式：
#   curl -sSL https://chuilishi2.github.io/run.sh | bash -s -- <hfdownloader 参数>
#
# 依赖：
#   - bash, curl, python3, pip (可选)
#   - cloudpan189-go Linux 可执行文件（在存储桶中）
#   - cloud189_config.json（存储桶中，内含已登录/扫码后的认证信息）
#
# 变量说明：
#   BUCKET_BASE          存储桶中 main.py/cloudpan189-go/cloud189_config.json 的基础 URL
#                         例如："https://example-bucket.cos.ap-shanghai.myqcloud.com/auto/hf2cloudpan"
#   CLOUD_DEST_PATH      目标云盘保存路径，默认 /
#
# 示例：
#   BUCKET_BASE="https://my-bucket.domain/path" \
#   curl -sSL https://chuilishi2.github.io/run.sh | bash -s -- \
#     --repo stabilityai/stable-diffusion-2 \
#     --include "*.safetensors"
# ============================================================================
set -euo pipefail

# ----------------------- 用户可配置的变量 -----------------------
BUCKET_BASE="${BUCKET_BASE:-https://0b7605a25adebbe32083fa202b5e1237.r2.cloudflarestorage.com/cloudpan189}"
CLOUD_DEST_PATH="${CLOUD_DEST_PATH:-/}"
CONFIG_DIR="${CLOUD189_CONFIG_DIR:-$HOME/.config/cloudpan189-go}"

# ----------------------- 下载依赖 -------------------------------
WORKDIR="$(pwd)"
mkdir -p "$WORKDIR" "$CONFIG_DIR"

_download_if_absent() {
  local url="$1"
  local out="$2"
  if [[ ! -f "$out" ]]; then
    echo "[INFO] Downloading $(basename "$out") …"
    curl -# -L "$url" -o "$out"
    chmod +x "$out" 2>/dev/null || true
  fi
}

_download_if_absent "$BUCKET_BASE/main.py" "$WORKDIR/main.py"
_download_if_absent "$BUCKET_BASE/cloudpan189-go" "$WORKDIR/cloudpan189-go"
_download_if_absent "$BUCKET_BASE/cloud189_config.json" "$CONFIG_DIR/cloud189_config.json"

export CLOUD189_CONFIG_DIR="$CONFIG_DIR"
export PATH="$WORKDIR:$PATH"

# ----------------------- Python 依赖 ---------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERROR] python3 未安装，请先安装 python3 环境。"
  exit 1
fi

# 安装必要的第三方库（如果缺失）
python3 - <<'PY'
import importlib, subprocess, sys
for pkg in ("huggingface_hub",):
    try:
        importlib.import_module(pkg)
    except ModuleNotFoundError:
        print(f"[INFO] Installing {pkg} …")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", pkg])
PY

# ----------------------- hfdownloader 安装 -----------------------
if ! command -v hfdownloader &>/dev/null; then
  echo "[INFO] Installing hfdownloader …"
  curl -sSL https://g.bodaay.io/hfd | bash -s -- -i
fi

# 确保安装路径在 PATH 中
auto_paths=("$HOME/.local/bin" "/usr/local/bin")
for p in "${auto_paths[@]}"; do
  [[ ":$PATH:" != *":${p}:"* ]] && export PATH="${p}:$PATH"
done

# ----------------------- 执行主流程 ----------------------------
python3 "$WORKDIR/main.py" --dest-path "$CLOUD_DEST_PATH" "$@"
