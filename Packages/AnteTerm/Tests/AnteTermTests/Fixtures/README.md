# Golden fixtures

Raw PTY byte streams recorded with `scripts/record-fixture.py`. Each shell ran under Ante's
integration shim with a throwaway `$HOME` and rc directory that only pin a fixed prompt, and the harness typed
each command only after the shell emitted its input-start marker (OSC 133;B):

    true
    false
    cd /tmp
    exit

`GoldenFixtureTests` asserts the *shape* of the semantic events (prompt/command/exit-code
sequence and the final `cd /tmp`), not machine-specific paths. Re-record with the script when
the integration files change; never hand-edit a `.bytes` file.

| file             | shell      | recorded on macOS |
|------------------|------------|-------------------|
| zsh-basic.bytes  | /bin/zsh   | 26.6              |
| bash-basic.bytes | /bin/bash  | 26.6              |
