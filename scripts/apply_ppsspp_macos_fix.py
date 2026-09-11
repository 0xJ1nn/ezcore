#!/usr/bin/env python3
"""Idempotent macOS-arm64 adaptation of PPSSPP's libretro/Makefile.common.

Upstream gaps (both macOS-only, both verified against the failing builds):
1. libadrenotools (Android linker shim) compiles for every
   TARGET_ARCH=arm64, including macOS where <android/api-level.h>
   does not exist -> guard to android platforms.
2. -DHAVE_STRONG_GETAUXVAL is set for every non-android/non-win32
   platform, but <sys/auxv.h> is Linux-only -> macOS uses the dlfcn
   probe (same as Android).

Usage: apply_ppsspp_macos_fix.py <ppsspp-checkout-root>
Exits 0 whether or not changes were needed.
"""
import sys

MARK = "EMU_MACOS_ARM64"


def _has(lines: list[str], token: str) -> bool:
    return any(token in line for line in lines)


def main(root: str) -> int:
    path = f"{root}/libretro/Makefile.common"
    with open(path) as f:
        lines = f.readlines()

    if _has(lines, MARK + "_PNG"):
        print("already adapted, skipping")
        return 0

    out: list[str] = []
    i = 0
    guarded_adreno = False
    darwin_branch = False
    while i < len(lines):
        line = lines[i]
        # 1. Wrap the adrenotools arm64 block.
        if (not guarded_adreno
                and line.startswith("ifeq ($(TARGET_ARCH),arm64)")
                and i + 1 < len(lines)
                and "libadrenotools" in lines[i + 2]):
            out.append(f"# {MARK}: adrenotools is Android-only\n")
            out.append("ifneq (,$(findstring android,$(platform)))\n")
            # Copy through the matching endif.
            while True:
                out.append(lines[i])
                done = lines[i].strip() == "endif"
                i += 1
                if done:
                    break
            out.append("endif\n")
            guarded_adreno = True
            continue
        # 2. Add the darwin dlfcn branch before the GETAUXVAL fallback.
        if (not darwin_branch
                and line.startswith("else ifneq ($(PLATFORM_EXT), win32)")
                and i + 1 < len(lines)
                and "HAVE_STRONG_GETAUXVAL" in lines[i + 1]):
            out.append(f"# {MARK}: macOS has dlfcn but no <sys/auxv.h>\n")
            out.append("else ifeq ($(PLATFORM_EXT), darwin)\n")
            out.append("COREFLAGS += -DHAVE_DLFCN_H\n")
            darwin_branch = True
        out.append(line)
        i += 1

    if not (guarded_adreno and darwin_branch):
        print(f"REFUSED: anchors not found "
              f"(adreno={guarded_adreno} darwin={darwin_branch})",
              file=sys.stderr)
        return 1

    # 3. No NEON assembly sources are wired for osx-arm64 (the arm/ list
    # lives in the 32-bit branch); disable the libpng NEON reference.
    # PNG filtering is not hot (texture decode only).
    out.append(f"\n# {MARK}_PNG: no NEON asm wired for osx-arm64\n")
    out.append("ifeq ($(TARGET_ARCH),arm64)\n")
    out.append("ifneq (,$(findstring osx,$(platform)))\n")
    out.append("CPUFLAGS += -DPNG_ARM_NEON_OPT=0\n")
    out.append("endif\n")
    out.append("endif\n")

    with open(path, "w") as f:
        f.writelines(out)
    print("adapted Makefile.common for macOS-arm64")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
