#!/usr/bin/env bash
set -euo pipefail

# ---------------- 用户可配置 -----------------
BUCKET_BASE="${BUCKET_BASE:-https://0b7605a25adebbe32083fa202b5e1237.r2.cloudflarestorage.com/cloudpan189}"
CLOUD_DEST_PATH="${CLOUD_DEST_PATH:-/}"
CONFIG_DIR="${CLOUD189_CONFIG_DIR:-$HOME/.config/cloudpan189-go}"

# ---------------- 前置准备 -------------------
WORKDIR="$(pwd)"
mkdir -p "$WORKDIR" "$CONFIG_DIR"

download_if_absent() {
  [[ -f $2 ]] || { echo "[DL] $(basename "$2")"; curl -sSL "$1" -o "$2"; chmod +x "$2" 2>/dev/null || true; }
}

download_if_absent "$BUCKET_BASE/cloudpan189-go" "$WORKDIR/cloudpan189-go"
download_if_absent "$BUCKET_BASE/cloud189_config.json" "$CONFIG_DIR/cloud189_config.json"

export CLOUD189_CONFIG_DIR="$CONFIG_DIR"
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

# ----------- 下载前快照 -------------
mapfile -t PRE < <(find . -maxdepth 1 -mindepth 1 -printf '%P\n')

# ----------- 执行下载 ---------------
echo "[INFO] running: hfdownloader ${HF_ARGS[*]}"
hfdownloader "${HF_ARGS[@]}"

# ----------- 判断上传对象 ----------
STORAGE=""
# 1) 若用户显式指定 -s / --storage
for ((i=0;i<${#HF_ARGS[@]};i++)); do
  if [[ ${HF_ARGS[i]} == "-s" ]] && (( i+1<${#HF_ARGS[@]} )); then
      STORAGE="${HF_ARGS[i+1]}"; break
  elif [[ ${HF_ARGS[i]} == --storage=* ]]; then
      STORAGE="${HF_ARGS[i]#*=}"; break
  elif [[ ${HF_ARGS[i]} == "--storage" ]] && (( i+1<${#HF_ARGS[@]} )); then
      STORAGE="${HF_ARGS[i+1]}"; break
  fi
done

TARGET=""
if [[ -n $STORAGE ]]; then
  TARGET="$STORAGE"
else
  mapfile -t POST < <(find . -maxdepth 1 -mindepth 1 -printf '%P\n')
  mapfile -t NEW < <(comm -13 <(printf '%s\n' "${PRE[@]}" | sort) <(printf '%s\n' "${POST[@]}" | sort))
  [[ ${#NEW[@]} == 1 ]] && TARGET="${NEW[0]}" || TARGET="."
fi

# ----------- 上传 -------------------
echo "[INFO] uploading $TARGET → $DEST_PATH"
cloudpan189-go upload $OW_FLAG "$TARGET" "$DEST_PATH"
