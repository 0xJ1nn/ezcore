import 'dart:io';

/// Validates that a file is a plausible ROM image, not a text file or
/// unrelated data file that happens to share a ROM extension.
///
/// The catalog maps extensions to cores, but many extensions are ambiguous
/// (`.md`, `.fig`, `.bin`, `.iso`, `.zip`, `.exe`, `.com`, `.bat`, `.img`,
/// `.lst`, `.m3u`, `.pbp`, `.elf`, `.dol`, `.wad`, `.cso`, `.ciso`, `.rvz`,
/// `.gcm`, `.cdi`, `.gdi`, `.ccd`, `.chd`, `.cue`, `.sg`, `.gg`, `.sms`,
/// `.gen`, `.pce`, `.sgx`, `.a26`, `.nes`, `.fds`, `.unf`, `.n64`, `.z64`,
/// `.v64`, `.sfc`, `.smc`, `.gb`, `.gbc`, `.gba`, `.nds`, `.scummvm`,
/// `.prx`, `.wbfs`). Without content validation, a `README.TXT` or
/// `GPLv2.txt` in a ROM folder gets imported as a "game".
///
/// Validation strategy (in order):
/// 1. Reject empty files.
/// 2. Text-by-spec formats (cue, ccd, gdi, lst, m3u, scummvm, bat):
///    accept iff the file looks like text — a real one *is* text; a
///    binary file wearing the extension is an impostor.
/// 3. Reject files that are too small to be a real ROM (< 512 bytes).
/// 4. Reject files that are too large to be a ROM (> 512 MB).
/// 5. Reject files that are mostly text (READMEs, licenses, notes).
/// 6. Accept files with known ROM magic bytes at their real offsets
///    (ISO PVD at 0x8000, Sega header at 0x7FF0, cart logos inside the
///    header block).
/// 7. Accept files that are binary (non-text) and within size bounds
///    for headerless formats (raw carts, disc system areas).
class RomValidator {
  const RomValidator();

  /// Minimum plausible ROM size in bytes (512 bytes).
  static const minRomSize = 512;

  /// Maximum plausible ROM size in bytes (512 MB).
  static const maxRomSize = 512 * 1024 * 1024;

  /// Head window read for classification. Must cover the deepest magic
  /// offset in the table (ISO9660 PVD at 0x8000, Sega "TMR SEGA" at
  /// 0x7FF0) — a 512-byte window meant those checks could never match
  /// a real file.
  static const _headWindow = 0x8000 + 32;

  /// Formats that are text by specification. A bundled core declares
  /// these extensions, so a mostly-text file carrying one of them is
  /// plausible playable content (cue sheets, playlists, CloneCD/GDI
  /// descriptors, ScummVM info files, DOS .bat launchers). A *binary*
  /// file wearing one of these extensions is an impostor — the inverse
  /// gate of the binary formats below.
  static const _textBySpec = {
    'cue', 'ccd', 'gdi', 'lst', 'm3u', 'scummvm', 'bat',
  };

  /// Known ROM magic bytes. Each entry is a list of (offset, bytes) checks.
  /// The first matching check accepts the file. Entries with an offset > 0
  /// describe header fields that live inside the cart (GB/GBC Nintendo logo
  /// at 0x104, Genesis "SEGA" at 0x100, GBA logo at 0x04) — checking them
  /// at offset 0 only worked for synthetic test files, never real ROMs.
  static const _magicBytes = <String, List<(int, List<int>)>>{
    // NES: "NES\x1A" (iNES header)
    'nes': [
      (0, [0x4E, 0x45, 0x53, 0x1A]),
    ],
    // GB/GBC: Nintendo logo bytes at 0x104-0x133 (48 bytes)
    'gb': [
      (0x104, [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B]),
    ],
    'gbc': [
      (0x104, [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B]),
    ],
    // GBA: Nintendo logo bytes at 0x04-0x9F (156 bytes)
    'gba': [
      (0x04, [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21]),
    ],
    // SNES/SFC: 0x78 0x56 0x34 0x12 (checksum) or "SNES"
    'sfc': [
      (0, [0x78, 0x56, 0x34, 0x12]),
      (0, [0x53, 0x4E, 0x45, 0x53]),
    ],
    // N64 family: all three standard byte orders. Collections mix them
    // and any of .n64/.z64/.v64 may carry any of them — a dump in the
    // wrong order for its extension must still import.
    'n64': [
      (0, [0x80, 0x37, 0x12, 0x40]), // z64 big-endian (native)
      (0, [0x40, 0x12, 0x37, 0x80]), // .n64 little-endian
      (0, [0x37, 0x80, 0x40, 0x12]), // .v64 byte-swapped
      (0, [0x4E, 0x55, 0x53, 0x00]),
    ],
    // Genesis/MD: "SEGA" at 0x100-0x103
    'md': [
      (0x100, [0x53, 0x45, 0x47, 0x41]),
    ],
    // SMS: Sega header "TMR SEGA" at 0x7FF0 (real ROMs carry it there,
    // not at 0x100 — dumps of master system carts have code at 0x100)
    'sms': [
      (0x7FF0, [0x54, 0x4D, 0x52, 0x20, 0x53, 0x45, 0x47, 0x41]),
      (0x100, [0x53, 0x45, 0x47, 0x41]),
    ],
    // GG: Sega header "TMR SEGA" at 0x7FF0
    'gg': [
      (0x7FF0, [0x54, 0x4D, 0x52, 0x20, 0x53, 0x45, 0x47, 0x41]),
      (0x100, [0x53, 0x45, 0x47, 0x41]),
    ],
    // PCE: "PCE\x00" (no magic on many carts — binary check fallback)
    'pce': [
      (0, [0x50, 0x43, 0x45, 0x00]),
    ],
    // NDS: Nintendo logo at 0xC0 (byte 0 is the ARM9 entrypoint — no
    // signature there on real dumps); legacy offset-0 checks kept.
    'nds': [
      (0xC0, [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21]),
      (0, [0x4E, 0x44, 0x53, 0x00]),
      (0, [0x24, 0xFF, 0xAE, 0x51]),
    ],
    // A26: "ATARI\x00" header (superchip-style carts); plain 4K/2K carts
    // have no header at all — they pass via the headerless-binary fallback.
    'a26': [
      (0, [0x41, 0x54, 0x41, 0x52, 0x49, 0x00]),
    ],
    // DOS: "MZ" (PE header)
    'exe': [
      (0, [0x4D, 0x5A]),
    ],
    // COM: binary check, no magic
    'com': [
      (0, [0x00, 0x00, 0x00, 0x00]),
    ],
    // IMG: binary check
    'img': [
      (0, [0x00, 0x00, 0x00, 0x00]),
    ],
    // ISO9660: Primary Volume Descriptor at 0x8000 = 0x01 "CD001"
    // (16 reserved sectors precede it; byte 0 is system-area zeros on
    // real discs, so an offset-0 check never matched a real .iso).
    'iso': [
      (0x8000, [0x01, 0x43, 0x44, 0x30, 0x30, 0x31]),
      (0, [0x01, 0x43, 0x44, 0x30, 0x30, 0x31]),
    ],
    // CHD: "MComprHD" (MAME CHD)
    'chd': [
      (0, [0x4D, 0x43, 0x6F, 0x6D, 0x70, 0x72, 0x48, 0x44]),
    ],
    // CSO: 0x43 0x49 0x53 0x4F (CISO)
    'cso': [
      (0, [0x43, 0x49, 0x53, 0x4F]),
    ],
    // PBP: 0x00 0x50 0x42 0x50 (PBP)
    'pbp': [
      (0, [0x00, 0x50, 0x42, 0x50]),
    ],
    // ELF: 0x7F 0x45 0x4C 0x46 (ELF)
    'elf': [
      (0, [0x7F, 0x45, 0x4C, 0x46]),
    ],
    // PRX: 0x00 0x50 0x52 0x58 (PRX)
    'prx': [
      (0, [0x00, 0x50, 0x52, 0x58]),
    ],
    // DOL: 0x00 0xD0 0x0D 0xFE (DOL)
    'dol': [
      (0, [0x00, 0xD0, 0x0D, 0xFE]),
    ],
    // WAD: IWAD (base game) or PWAD (mods — playable content too)
    'wad': [
      (0, [0x49, 0x57, 0x41, 0x44]),
      (0, [0x50, 0x57, 0x41, 0x44]),
    ],
    // WBFS: 0x57 0x42 0x46 0x53 (WBFS)
    'wbfs': [
      (0, [0x57, 0x42, 0x46, 0x53]),
    ],
    // RVZ: 0x52 0x56 0x5A 0x01 (RVZ)
    'rvz': [
      (0, [0x52, 0x56, 0x5A, 0x01]),
    ],
    // GCM: 0x47 0x43 0x4D 0x00 (GCM)
    'gcm': [
      (0, [0x47, 0x43, 0x4D, 0x00]),
    ],
    // CISO: 0x43 0x49 0x53 0x4F (CISO)
    'ciso': [
      (0, [0x43, 0x49, 0x53, 0x4F]),
    ],
    // CDI: 0x43 0x44 0x49 0x00 (CDI)
    'cdi': [
      (0, [0x43, 0x44, 0x49, 0x00]),
    ],
    // ZIP: 0x50 0x4B 0x03 0x04 (PK\x03\x04)
    'zip': [
      (0, [0x50, 0x4B, 0x03, 0x04]),
    ],
    // FDS: 0x46 0x44 0x53 0x1A (FDS)
    'fds': [
      (0, [0x46, 0x44, 0x53, 0x1A]),
    ],
    // UNF: UNIF container magic "UNIF"
    'unf': [
      (0, [0x55, 0x4E, 0x49, 0x46]),
    ],
    // V64: byte-swapped order first, other standard orders accepted
    'v64': [
      (0, [0x37, 0x80, 0x40, 0x12]),
      (0, [0x80, 0x37, 0x12, 0x40]),
      (0, [0x40, 0x12, 0x37, 0x80]),
    ],
    // Z64: native big-endian first, other standard orders accepted
    'z64': [
      (0, [0x80, 0x37, 0x12, 0x40]),
      (0, [0x40, 0x12, 0x37, 0x80]),
      (0, [0x37, 0x80, 0x40, 0x12]),
    ],
    // SG: "SEGA" at 0x100-0x103
    'sg': [
      (0x100, [0x53, 0x45, 0x47, 0x41]),
    ],
    // SGX: "PCE\x00" or binary check
    'sgx': [
      (0, [0x50, 0x43, 0x45, 0x00]),
    ],
    // FIG: binary check
    'fig': [
      (0, [0x00, 0x00, 0x00, 0x00]),
    ],
    // GEN: "SEGA" at 0x100-0x103
    'gen': [
      (0x100, [0x53, 0x45, 0x47, 0x41]),
    ],
    // BIN: binary check
    'bin': [
      (0, [0x00, 0x00, 0x00, 0x00]),
    ],
  };

  /// Validates that [filePath] is a plausible ROM image.
  ///
  /// Returns `true` if the file passes validation, `false` otherwise.
  /// The [extension] is used to select the appropriate magic-byte check.
  Future<bool> validate(String filePath, String extension) async {
    final file = File(filePath);
    if (!file.existsSync()) return false;

    final stat = await file.stat();
    final size = stat.size;

    // Reject empty files
    if (size == 0) return false;

    final ext = extension.toLowerCase();

    // Read enough of the head to cover every magic offset in the table
    // (ISO9660 PVD at 0x8000, Sega header at 0x7FF0) plus the text
    // sample. Shorter reads meant those checks never matched a real
    // file regardless of their table entries.
    final bytes = await file.openRead(0, _headWindow).first;
    if (bytes.isEmpty) return false;
    final looksText = _isTextFile(bytes);

    // Text-by-spec formats: a real cue/playlist/descriptor/launcher IS
    // text — accept it; reject binary impostors (inverse gate).
    if (_textBySpec.contains(ext)) {
      if (size > maxRomSize) return false;
      return looksText;
    }

    // Reject files that are too small to be a real ROM
    if (size < minRomSize) return false;

    // Reject files that are too large to be a ROM
    if (size > maxRomSize) return false;

    // Reject text files (READMEs, licenses, notes, etc.)
    if (looksText) return false;

    // Check magic bytes for the extension
    final magicList = _magicBytes[ext];
    if (magicList == null || magicList.isEmpty) {
      // No magic bytes defined for this extension — accept if binary
      return true;
    }

    // Each check is (offset, bytes): the file is accepted when any
    // check's bytes match at its offset. Headerless formats (plain 2600
    // carts) need the offset-0 fallback below; cart-embedded headers (GB
    // logo at 0x104, Genesis "SEGA" at 0x100) are checked at their real
    // offsets.
    for (final (offset, magic) in magicList) {
      if (bytes.length >= offset + magic.length &&
          _matchesMagic(bytes.sublist(offset), magic)) {
        return true;
      }
    }

    // No magic matched. Headerless cart/disc formats (no reliable
    // signature in their spec) stay acceptable as binary — content
    // validation still rejects text/empty/oversized files above.
    return _isHeaderlessFormat(ext);
  }

  /// Formats whose dumps carry no reliable identifying signature in the
  /// first bytes of the file (plain Atari 2600 carts, raw dumps like
  /// .bin/.fig/.com/.img, SNES LoROM/HiROM headers at 0x7FC0/0xFFC0,
  /// disc system areas, container dumps). Anything binary within the
  /// size bounds is plausible content for these; text impostors are
  /// still rejected above.
  static bool _isHeaderlessFormat(String ext) => const {
        'a26', 'bin', 'fig', 'com', 'img', 'pce', 'sgx',
        // raw carts / no byte-0 signature:
        'sg', 'sfc', 'smc',
        // container/disc dumps without a canonical byte-0 magic:
        'dol', 'gcm', 'cdi', 'rvz', 'pbp', 'prx',
      }.contains(ext);

  /// Returns `true` if [bytes] look like a text file (ASCII/UTF-8).
  ///
  /// A file is considered text if > 90% of its bytes are printable ASCII
  /// or common whitespace (tab, newline, carriage return).
  bool _isTextFile(List<int> bytes) {
    if (bytes.isEmpty) return true;

    var textBytes = 0;
    for (final byte in bytes) {
      if ((byte >= 0x20 && byte <= 0x7E) || // printable ASCII
          byte == 0x09 || // tab
          byte == 0x0A || // newline
          byte == 0x0D) {
        // carriage return
        textBytes++;
      }
    }

    final ratio = textBytes / bytes.length;
    return ratio > 0.90;
  }

  /// Returns `true` if [bytes] start with [magic].
  bool _matchesMagic(List<int> bytes, List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}
