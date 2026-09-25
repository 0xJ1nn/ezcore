#!/usr/bin/env python3
"""Standalone release gate for bundled core artwork."""
from license_audit import verify_core_art


def main() -> int:
    violations = verify_core_art()
    if violations:
        print("core artwork verification failed:")
        for violation in violations:
            print(f"  ✗ {violation}")
        return 1
    print("core artwork: provenance, file set, pins, and WebP headers OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
