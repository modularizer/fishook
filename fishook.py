import os
import subprocess
import sys
import sysconfig
from pathlib import Path

def _fishook_sh() -> str:
    data_dir = Path(sysconfig.get_path("data"))
    return str(data_dir / "share" / "fishook" / "fishook.sh")


def _run_sh(args: list[str]) -> int:
    # Execute fishook.sh with passed args
    sh = _fishook_sh()
    # Ensure executable bit isn't required on Windows; run via bash.
    bash = os.environ.get("BASH", "bash")
    return subprocess.call([bash, sh, *args])

def main() -> None:
    # fishook <args...>
    raise SystemExit(_run_sh(sys.argv[1:]))
