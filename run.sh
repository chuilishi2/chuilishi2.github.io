#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Install the required Python package
pip install --upgrade pip wheel >/dev/null 2>&1 || true
pip install --upgrade aligo

# 若系统中未找到 hfdownloader，则自动安装
if ! command -v hfdownloader &>/dev/null; then
  echo "[INFO] Installing hfdownloader …"
  # 安装脚本将 hfdownloader 放到 /usr/local/bin 或 ~/.local/bin
  curl -sSL https://g.bodaay.io/hfd | bash -s -- -i
  # 将常见安装路径加入 PATH，确保当前会话可直接访问
  export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
fi

# 下载并执行远程 main.py，将所有用户传入的参数原样转发
curl -sSL https://chuilishi2.github.io/main.py | python3 - "$@" 
