# GTA Converter - Local Engine Porting Notes

## Source audit

The reference engine is in `tmoath07-svg/Ps4tools`, inside `ZokiiStudio-Toolkit-FIXED.zip`. The audit workflow extracts source-only files and records SHA-256 hashes, Python syntax, imports, symbols, and Windows-specific markers. It does not execute the supplied Windows binaries.

### Existing conversion pipeline

1. `7N-RL_One_IRAQ.py` orchestrates vehicle/DLC packaging, recursive RPF extraction and rebuilding, metadata generation/merging, and the final platform-folder change from `x64` to `ps4`.
2. `core_converter.py` handles the structural Y* to O* resource pass. For supported RSC7 files it preserves the 16-byte header, decompresses the payload, patches the PC/PS4 platform marker table, raw-DEFLATE recompresses the payload, and writes the new extension.
3. YTD processing is a separate pipeline: decode RSC7, parse texture dictionary entries, extract DDS data, enforce a texture-size policy, then invoke `ragebuilder.exe` with `texture_builder.lua` to compile an OTD.
4. `RPFBuilder/extract_rpf.py` is primarily Python/struct/zlib plus PyCryptodome AES. `extract_ytd.py` is primarily Python/struct/zlib.
5. `RPFBuilder/build_rpf.py` and `build_otd.py` are wrappers around `ragebuilder.exe`; the toolkit includes Windows DLLs such as `xg.dll`, `zlib.dll`, `libScePsr.dll`, `oo2tex.dll`, and related runtime components.

### Extension mapping found in the original structural converter

| PC input | PS4 output | Existing operation |
|---|---|---|
| .yft | .oft | RSC7 payload patch + raw-DEFLATE |
| .ydr | .odr | RSC7 payload patch + raw-DEFLATE |
| .ydd | .odd | RSC7 payload patch + raw-DEFLATE |
| .ypt | .opt | RSC7 payload patch + raw-DEFLATE |
| .ybn | .obn | RSC7 payload patch + raw-DEFLATE |
| .ybd | .obd | RSC7 payload patch + raw-DEFLATE |
| .yld | .old | RSC7 payload patch + raw-DEFLATE |
| .yed | .oed | RSC7 payload patch + raw-DEFLATE |
| .yfd | .ofd | RSC7 payload patch + raw-DEFLATE |
| .ynd | .ond | RSC7 payload patch + raw-DEFLATE |
| .ynv | .onv | RSC7 payload patch + raw-DEFLATE |
| .yvr | .ovr | RSC7 payload patch + raw-DEFLATE |
| .ywr | .owr | RSC7 payload patch + raw-DEFLATE |
| .ypdb | .opdb | RSC7 payload patch + raw-DEFLATE |
| .ycd | .ocd | Extension conversion/copy |
| .ymap | .omap | Extension conversion/copy |
| .ytyp | .otyp | Extension conversion/copy |
| .ymt | .omt | Extension conversion/copy |
| .ymf | .omf | Extension conversion/copy |
| .ytd | .otd | Texture extraction + native ragebuilder compilation |

These are the operations observed in the reference scripts, not a claim that every renamed file is automatically valid. Each output needs format-level validation.

## iOS port strategy

- Keep archive parsing/building in a static Rust library linked into the iOS executable.
- Keep file selection, security-scoped access, progress, reports, and sharing in SwiftUI.
- Port the pure-data Python logic first: safe scanning, metadata parsing/merging, RSC7 header parsing, raw-DEFLATE processing, RPF extraction and validation.
- Replace the Windows-only RPF/texture builder with a native implementation or a documented, tested compatible library. Do not bundle or attempt to execute PE executables/DLLs on iOS.
- Use test fixtures and round-trip checks for every format before enabling a conversion button.

## Current implementation: 0.1.0

The new `LocalEngine` Rust static library currently provides:

- RPF header/table inspection for supported unencrypted archives.
- Generic unencrypted RPF7 building from a selected directory.
- Re-parse validation of the generated archive.
- Native structural conversion for the observed Y* to O* extension map: RSC7 header preservation, raw/zlib/gzip DEFLATE detection, PC-to-PS4 marker replacement, and raw-DEFLATE recompression.
- Extension-only conversion for the non-patched types observed in the source scripts.
- File count, recursion depth, and total input-size limits.
- Symlink skipping and path traversal checks.

The SwiftUI local engine screen is wired to these functions. The build workflow compiles the Rust static library for `aarch64-apple-ios`, runs Rust tests, links it into the unsigned IPA, and verifies the exported C ABI symbol.

## Explicitly not complete yet

- The structural RSC7 patch has only unit-level synthetic tests so far; it still needs real, legally supplied fixture files and byte-for-byte comparison against the reference converter.
- No YTD-to-OTD compiler has been implemented yet.
- Generic RPF7 creation is not equivalent to a validated PS4 DLC build.
- Cloud conversion remains available as a temporary fallback until local outputs pass fixture tests and in-game validation.
