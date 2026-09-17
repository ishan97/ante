#!/usr/bin/env python3
"""Records raw PTY bytes from a shell running under Ante's integration shim.

Usage: scripts/record-fixture.py zsh|bash <output.bytes>

The shell runs with a throwaway HOME and rc directory (holding only a fixed prompt) so the
capture is portable and carries no user or host name.
Each command is typed only after the shell has emitted its input-start marker (OSC 133;B),
which is how a human would type — so the recording is deterministic.
"""
import os
import pty
import select
import shutil
import sys
import tempfile
import time

COMMANDS = [b"true\n", b"false\n", b"cd /tmp\n", b"exit\n"]
INPUT_START = b"\x1b]133;B\x07"
TIMEOUT_SECONDS = 10


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("zsh", "bash"):
        print(__doc__, file=sys.stderr)
        return 2
    shell, out_path = sys.argv[1], sys.argv[2]
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.join(repo, "Packages/AnteTerm/Sources/AnteTerm/Resources/Integration")

    # Under /tmp, not the per-user $TMPDIR, so the recording carries no account-specific path.
    with tempfile.TemporaryDirectory(dir="/tmp") as root:
        for d in ("zsh", "bash", "home", "empty-rc"):
            os.makedirs(os.path.join(root, d))
        for name, installed in (("zshenv", ".zshenv"), ("zprofile", ".zprofile"),
                                ("zshrc", ".zshrc"), ("ante-integration.zsh", "ante-integration.zsh")):
            shutil.copy(os.path.join(src, "zsh", name), os.path.join(root, "zsh", installed))
        shutil.copy(os.path.join(src, "bash/ante-bash.sh"), os.path.join(root, "bash/ante-bash.sh"))

        env = {
            "HOME": os.path.join(root, "home"),
            "PATH": "/usr/bin:/bin",
            "TERM": "xterm-256color",
            "ANTE_SHELL_INTEGRATION": "1",
        }
        # macOS's /etc/zshrc and /etc/bashrc set a "user@host" prompt after the environment is
        # read; the throwaway rc files below run later and pin a fixed prompt so the recording
        # never contains a user or host name.
        with open(os.path.join(root, "empty-rc", ".zshrc"), "w") as f:
            f.write("PROMPT='%% '\n")
        with open(os.path.join(root, "home", ".bash_profile"), "w") as f:
            f.write("PS1='$ '\n")
        if shell == "zsh":
            env["ZDOTDIR"] = os.path.join(root, "zsh")
            env["ANTE_USER_ZDOTDIR"] = os.path.join(root, "empty-rc")
            argv = ["/bin/zsh", "-l"]
        else:
            argv = ["/bin/bash", "--init-file", os.path.join(root, "bash/ante-bash.sh")]

        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(env["HOME"])
            os.execve(argv[0], argv, env)

        captured = bytearray()
        pending = list(COMMANDS)
        since_last_send = bytearray()
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                captured += chunk
                since_last_send += chunk
            if pending and INPUT_START in since_last_send:
                os.write(fd, pending.pop(0))
                since_last_send = bytearray()
        os.waitpid(pid, 0)

    with open(out_path, "wb") as f:
        f.write(captured)
    print(f"recorded {len(captured)} bytes to {out_path}")
    return 0 if not pending else 1


if __name__ == "__main__":
    sys.exit(main())
