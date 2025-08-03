import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
import platform
from datetime import datetime
import logging

from aligo import Aligo
from aligo.types import Null
from aligo.types import EMailConfig

# 固定邮箱配置（用于扫码邮件登录，可按需修改）
EMAIL_CFG = EMailConfig(
    email="1483843127@qq.com",
    user="1483843127@qq.com",
    password="xyajfiybhnwwgfgd",
    host="smtp.qq.com",
    port=465,
)


def explicit_storage_path(hf_args: list[str]) -> Path | None:
    """Return storage path if user explicitly set -s/--storage, else None."""
    if "-s" in hf_args:
        idx = hf_args.index("-s")
        if idx + 1 < len(hf_args):
            return Path(hf_args[idx + 1]).expanduser().resolve()
    if "--storage" in hf_args:
        idx = hf_args.index("--storage")
        if idx + 1 < len(hf_args):
            return Path(hf_args[idx + 1]).expanduser().resolve()
    return None


def detect_new_items(start_snapshot: set[Path]) -> list[Path]:
    """Return list of new top-level items created after download."""
    current = {p for p in Path.cwd().iterdir() if not p.name.startswith('.')}
    return sorted(current - start_snapshot, key=lambda p: p.name)


def ensure_hfdownloader_available():
    """Check that the `hfdownloader` binary is on PATH."""
    if shutil.which("hfdownloader") is None:
        print("[WARN] hfdownloader 未找到，尝试自动安装 …")
        if not install_hfdownloader():
            raise EnvironmentError(
                "hfdownloader binary not found and auto-install failed. "
                "请手动安装：https://github.com/bodaay/HuggingFaceModelDownloader"
            )


def run_hfdownloader(hf_args: list[str]):
    """Execute hfdownloader with the provided arguments."""
    cmd = ["hfdownloader", *hf_args]
    print("[INFO] Running:", " ".join(cmd))
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as exc:
        print("[ERROR] hfdownloader failed.")
        sys.exit(exc.returncode)


def ensure_aliyun_login() -> Aligo:
    """Return a logged-in Aligo client; exit if not logged in or token expired."""
    try:
        # 始终携带邮箱配置，若需要重新登录会自动把二维码发送到邮箱
        ali = Aligo(email=EMAIL_CFG, level=logging.INFO)  # token 有效直接通过；无效则扫码/邮件登录
        info = ali.get_personal_info()
        if isinstance(info, Null):
            raise RuntimeError
        return ali
    except Exception:
        print("[ERROR] 无法完成登录，请检查网络或手动执行 `aligo` 登录后重试。")
        sys.exit(1)


def upload_to_aliyun(local_path: Path, parent_file_id: str, drive_id: str | None):
    """Upload `local_path` (file or directory) to Aliyun Drive using aligo."""
    ali = ensure_aliyun_login()
    if local_path.is_dir():
        print(f"[INFO] Uploading folder {local_path} to Aliyun Drive…")
        ali.upload_folder(
            folder_path=str(local_path),
            parent_file_id=parent_file_id,
            drive_id=drive_id,
        )
    else:
        print(f"[INFO] Uploading file {local_path} to Aliyun Drive…")
        ali.upload_file(
            file_path=str(local_path),
            parent_file_id=parent_file_id,
            drive_id=drive_id,
        )
    print("[INFO] Upload completed.")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Download model/dataset via hfdownloader and upload to Aliyun Drive.",
        add_help=False,  # we will forward unknown args to hfdownloader
    )
    # Known args for our wrapper
    parser.add_argument(
        "--parent-file-id",
        default="root",
        help="Target folder file_id in Aliyun Drive (default: root).",
    )
    parser.add_argument(
        "--drive-id",
        default=None,
        help="Aliyun Drive ID (default: use default drive).",
    )
    parser.add_argument("--help", "-h", action="store_true", help="Show this help message and hfdownloader help.")

    # Parse only our known args; rest are passed to hfdownloader
    known, remaining = parser.parse_known_args()

    # If user requested help, show combined help
    if known.help:
        parser.print_help()
        print("\n--- hfdownloader help below ---\n")
        subprocess.run(["hfdownloader", "--help"])
        sys.exit(0)

    return known, remaining


def install_hfdownloader() -> bool:
    """Attempt to install hfdownloader. Returns True on success."""
    try:
        if platform.system() == "Windows":
            # Prefer pwsh if available, else fallback to powershell.exe
            script_cmd = "iwr -useb https://g.bodaay.io/hfd | iex"
            shell = shutil.which("pwsh") or shutil.which("powershell")
            if not shell:
                print("[ERROR] 找不到 PowerShell，无法自动安装 hfdownloader。")
                return False
            print(f"[INFO] 使用 {shell} 自动安装 hfdownloader …")
            subprocess.run([shell, "-NoLogo", "-NoProfile", "-Command", script_cmd], check=True)
        else:
            print("[INFO] 使用 bash 自动安装 hfdownloader …")
            # 使用管道替代进程替换，兼容更多 shell 环境
            subprocess.run(["bash", "-c", "curl -sSL https://g.bodaay.io/hfd | bash -s -- -i"], check=True)
    except FileNotFoundError:
        print("[ERROR] 自动安装所需环境缺失（bash/curl 或 PowerShell）。")
        return False
    except subprocess.CalledProcessError:
        print("[ERROR] 自动安装 hfdownloader 失败。")
        return False

    # Refresh PATH lookup
    if shutil.which("hfdownloader") is not None:
        print("[INFO] hfdownloader 安装成功。")
        return True
    print("[ERROR] 自动安装后仍未找到 hfdownloader。")
    return False


def main():
    known, hf_args = parse_args()

    ensure_hfdownloader_available()

    # 提前登录，避免下载完成后才等待扫码/邮件
    ensure_aliyun_login()

    # snapshot before download
    pre_snapshot = {p for p in Path.cwd().iterdir() if not p.name.startswith('.')}

    # 1. Run hfdownloader
    run_hfdownloader(hf_args)

    # 2. Determine items to upload
    explicit_path = explicit_storage_path(hf_args)
    new_items = detect_new_items(pre_snapshot)

    if explicit_path:
        to_upload = explicit_path
    elif len(new_items) == 1:
        to_upload = new_items[0]
    else:
        to_upload = Path.cwd()

    if not to_upload.exists():
        print(f"[ERROR] Download seems to have failed: 未检测到下载结果。")
        sys.exit(1)

    upload_to_aliyun(
        local_path=to_upload,
        parent_file_id=known.parent_file_id,
        drive_id=known.drive_id,
    )


if __name__ == "__main__":
    main()
    

