# Test status

- On Linux/Windows: run `python scripts/validate.py` for source-level and YAML preflight assertions.
- Run `swiftc -frontend -parse Sources/*.swift` where Swift CLI is installed (syntax-only, **not** iOS build).
- Actual UIKit/WebKit conformance and linking require the included GitHub Actions macOS Xcode build.
- Real-device behavior requires manual checks in `VERIFY_ON_IPHONE.md`.

Do not interpret source checks as proof that the unsigned IPA can be installed, or that Float no longer crashes.
