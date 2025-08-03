#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# 安装/更新 aligo 依赖
pip install --upgrade pip wheel >/dev/null 2>&1 || true
pip install --upgrade aligo

# 下载并执行 remote main.py，将所有用户传入的参数原样转发
curl -sSL https://chuilishi2.github.io/main.py | python3 - "$@"
