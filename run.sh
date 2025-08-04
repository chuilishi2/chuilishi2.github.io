#!/usr/bin/env bash
set -euo pipefail

# ---------------- 用户可配置 -----------------
CLOUDPAN_BIN_URL="${CLOUDPAN_BIN_URL:-https://pub-c0ae33ad645240fda2e0ff56925c0436.r2.dev/cloudpan189-go}"
CLOUD_DEST_PATH="${CLOUD_DEST_PATH:-/}"
CONFIG_DIR="${CLOUD189_CONFIG_DIR:-$HOME/.config/cloudpan189-go}"

# ---------------- 前置准备 -------------------
WORKDIR="$(pwd)"
mkdir -p "$WORKDIR" "$CONFIG_DIR"

download_if_absent() {
  [[ -f $2 ]] || { echo "[DL] $(basename "$2")"; curl -sSL "$1" -o "$2"; chmod +x "$2" 2>/dev/null || true; }
}

download_if_absent "$CLOUDPAN_BIN_URL" "$WORKDIR/cloudpan189-go"

export CLOUD189_CONFIG_DIR="$CONFIG_DIR"
export HF_TOKEN="${HF_TOKEN:-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}"
export PATH="$WORKDIR:$HOME/.local/bin:/usr/local/bin:$PATH"

# ---- 自动安装 hfdownloader（如缺失） ----------
if ! command -v hfdownloader &>/dev/null; then
  echo "[INFO] Installing hfdownloader …"
  curl -sSL https://g.bodaay.io/hfd | bash -s -- -i
fi

# ---------------- 参数拆分 --------------------
DEST_PATH="$CLOUD_DEST_PATH"
OW_FLAG=""        # 是否覆盖
HF_ARGS=()        # 原样传递给 hfdownloader

while (( $# )); do
  case "$1" in
    --dest-path)
      DEST_PATH="$2"; shift 2 ;;
    --overwrite)
      OW_FLAG="-ow"; shift ;;
    --dest-path=* )
      DEST_PATH="${1#*=}"; shift ;;
    *)  HF_ARGS+=("$1"); shift ;;
  esac
done

if (( ${#HF_ARGS[@]} == 0 )); then
  echo "用法: run.sh [--dest-path /abc] [--overwrite] <hfdownloader 原生参数>"
  exit 1
fi

# ----------- 执行下载 ---------------
echo "[INFO] running: hfdownloader ${HF_ARGS[*]}"
hfdownloader "${HF_ARGS[@]}"

# ----------- 判断上传对象 ----------
STORAGE=""
MODEL_DATASET=""

for ((i=0;i<${#HF_ARGS[@]};i++)); do
  case "${HF_ARGS[i]}" in
    -s)
      (( i+1<${#HF_ARGS[@]} )) && STORAGE="${HF_ARGS[i+1]}" ;;
    --storage=*)
      STORAGE="${HF_ARGS[i]#*=}" ;;
    --storage)
      (( i+1<${#HF_ARGS[@]} )) && STORAGE="${HF_ARGS[i+1]}" ;;
    -m)
      (( i+1<${#HF_ARGS[@]} )) && MODEL_DATASET="${HF_ARGS[i+1]}" ;;
    --model=*)
      MODEL_DATASET="${HF_ARGS[i]#*=}" ;;
    --model)
      (( i+1<${#HF_ARGS[@]} )) && MODEL_DATASET="${HF_ARGS[i+1]}" ;;
    -d)
      (( i+1<${#HF_ARGS[@]} )) && MODEL_DATASET="${HF_ARGS[i+1]}" ;;
    --dataset=*)
      MODEL_DATASET="${HF_ARGS[i]#*=}" ;;
    --dataset)
      (( i+1<${#HF_ARGS[@]} )) && MODEL_DATASET="${HF_ARGS[i+1]}" ;;
  esac
done

# 若未指定模型或数据集，则直接退出（用于 -h 等场景）
if [[ -z $MODEL_DATASET ]]; then
  echo "[INFO] 未检测到 -m/--model 或 -d/--dataset 参数，跳过上传操作" >&2
  exit 0
fi

# 将 "/" 替换为 "_"，并去掉过滤器 ":filter" 部分
FOLDER="${MODEL_DATASET%%:*}"
FOLDER="${FOLDER//\//_}"

if [[ -n $STORAGE ]]; then
  TARGET="${STORAGE%/}"
  [[ -n $FOLDER ]] && TARGET="$TARGET/$FOLDER"
else
  TARGET="${FOLDER:-.}"
fi

# ----------- 校验目标是否存在 -----------
if [[ ! -e $TARGET ]]; then
  echo "[ERROR] 未找到下载生成的目录 $TARGET" >&2
  echo "[HINT] 请确认 hfdownloader 参数是否包含 -m/--model 或 -d/--dataset，且下载已成功完成" >&2
  exit 2
fi

# ----------- 上传 -------------------
echo "[INFO] uploading $TARGET → $DEST_PATH"
cloudpan189-go upload $OW_FLAG "$TARGET" "$DEST_PATH"
