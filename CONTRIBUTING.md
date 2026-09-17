# Contributing

Thanks for looking at Ante. Bug reports and pull requests are welcome.

## Building

    ./scripts/bootstrap.sh     # installs xcodegen, generates Ante.xcodeproj
    ./scripts/test.sh          # tests every package, then builds the app

Xcode 26 and the Metal toolchain are required (see `README.md`).

## Pull requests

- Keep each pull request to one change, with a test where the behaviour can be tested.
- Run `./scripts/test.sh` before opening it.
- Do not add code copied from other projects unless its licence is MIT-compatible and it is
  listed in `THIRD_PARTY_NOTICES.md`.
- Do not commit recorded terminal output, session files, or anything else from your own
  machine. Fixtures under `Packages/AnteTerm/Tests/AnteTermTests/Fixtures` are recorded with
  `scripts/record-fixture.py` in a throwaway home directory.

## Security

See `SECURITY.md`.
