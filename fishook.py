import os
import subprocess
import sys
from pathlib import Path

def _fishook_sh() -> str:
    # fishook.sh shipped inside the package as package data
    here = Path(__file__).resolve().parent
    sh = here / "fishook.sh"
    return str(sh)

def _run_sh(args: list[str]) -> int:
    # Execute fishook.sh with passed args
    sh = _fishook_sh()
    # Ensure executable bit isn't required on Windows; run via bash.
    bash = os.environ.get("BASH", "bash")
    return subprocess.call([bash, sh, *args])

def main() -> None:
    # fishook <args...>
    raise SystemExit(_run_sh(sys.argv[1:]))

# Hook convenience entrypoints (optional, but nice)
def _hook(name: str) -> None:
    raise SystemExit(_run_sh([name, *sys.argv[1:]]))

def hook_applypatch_msg(): _hook("applypatch-msg")
def hook_pre_applypatch(): _hook("pre-applypatch")
def hook_post_applypatch(): _hook("post-applypatch")

def hook_pre_commit(): _hook("pre-commit")
def hook_pre_merge_commit(): _hook("pre-merge-commit")
def hook_prepare_commit_msg(): _hook("prepare-commit-msg")
def hook_commit_msg(): _hook("commit-msg")
def hook_post_commit(): _hook("post-commit")

def hook_pre_rebase(): _hook("pre-rebase")
def hook_post_checkout(): _hook("post-checkout")
def hook_post_merge(): _hook("post-merge")
def hook_post_rewrite(): _hook("post-rewrite")

def hook_pre_push(): _hook("pre-push")
def hook_pre_auto_gc(): _hook("pre-auto-gc")

def hook_pre_receive(): _hook("pre-receive")
def hook_update(): _hook("update")
def hook_post_receive(): _hook("post-receive")
def hook_post_update(): _hook("post-update")
def hook_push_to_checkout(): _hook("push-to-checkout")
def hook_proc_receive(): _hook("proc-receive")

def hook_sendemail_validate(): _hook("sendemail-validate")
def hook_fsmonitor_watchman(): _hook("fsmonitor-watchman")
