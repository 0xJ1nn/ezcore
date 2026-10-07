import 'dart:io';

/// Identity of a candidate game file: its system when the content can be
/// recognized, or a rejection reason when the file is not playable ROM
/// content for any bundled core.
class RomIdentity {
  const RomIdentity({this.system, this.rejectReason});

  /// Catalog system id detected from content (e.g. `gb`, `wii`,
  /// `atari2600`), or null when the content is valid but its system can't
  /// be told apart (e.g. a plain ISO9660 image).
  final String? system;

  /// Set when the file must not import; the string is user-facing.
  final String? rejectReason;

  bool get rejected => rejectReason != null;
}

/// Validates that a file is a plausible ROM image, not a text file or
/// unrelated data file that happens to share a ROM extension — and
/// identifies which system the content actually belongs to.
///
/// The catalog maps extensions to cores, but many extensions are ambiguous
/// (`.gb` is claimed by GBA- and GB-first cores, `.bin` by Dreamcast and
/// Atari 2600, `.wad` by WiiWare, `.zip` by twelve cores, …). Extension
/// matching alone mislabels files: a Doom WAD lands in the GameCube shelf,
/// a PlayStation `.bin` in Dreamcast. Content beats extension here.
///
/// Validation strategy (in order):
/// 1. Reject empty files.
/// 2. Text-by-spec formats (cue, ccd, gdi, lst, m3u, scummvm, bat):
///    accept iff the file looks like text — a real one *is* text; a
///    binary file wearing the extension is an impostor.
/// 3. Reject files that are too small to be a real ROM (< 512 bytes).
/// 4. Reject files that are too large to be a ROM (> 512 MB).
/// 5. Reject files that are mostly text (READMEs, licenses, notes).
/// 6. Identify ambiguous content from its bytes (Nintendo/SEGA/N64
///    headers, Wii vs Doom WAD magic, DOS vs Windows executables, raw CD
///    tracks, archive contents) — see [identify].
/// 7. Accept files with known ROM magic bytes at their real offsets
///    (ISO PVD at 0x8000, Sega header at 0x7FF0, cart logos inside the
///    header block).
/// 8. Accept files that are binary (non-text) and within size bounds
///    for headerless formats (raw carts, disc system areas).
class RomValidator {
  const RomValidator();

  /// Minimum plausible ROM size in bytes (512 bytes).
  static const minRomSize = 512;

  /// Maximum plausible ROM size in bytes (512 MB).
  static const maxRomSize = 512 * 1024 * 1024;

  /// Head window read for classification. Must cover the deepest magic
  /// offset in the table (ISO9660 PVD at 0x8000, Sega "TMR SEGA" at
  /// 0x7FF0) plus the HiROM SNES checksum at 0xFFDE — a 512-byte window
  /// meant those checks could never match a real file.
  static const _headWindow = 0x10000 + 32;

  /// Formats that are text by specification. A bundled core declares
  /// these extensions, so a mostly-text file carrying one of them is
  /// plausible playable content (cue sheets, playlists, CloneCD/GDI
  /// descriptors, ScummVM info files, DOS .bat launchers). A *binary*
  /// file wearing one of these extensions is an impostor — the inverse
  /// gate of the binary formats below.
  static const _textBySpec = {
    'cue', 'ccd', 'gdi', 'lst', 'm3u', 'scummvm', 'bat',
  };

  /// Wii WAD (`WiiWare`) containers start with "Is"+version bytes.
  /// Doom IWAD/PWAD share the `.wad` extension but are a different beast
  /// entirely — the only `.wad` core is the GameCube/Wii one.
  static const _wiiWadMagic = [0x49, 0x73]; // "Is"
  static const _doomWads = [
    [0x49, 0x57, 0x41, 0x44], // IWAD
    [0x50, 0x57, 0x41, 0x44], // PWAD
  ];

  /// Raw CD-sector sync pattern (12 bytes at every 2352-byte sector).
  static const _cdSync =
      [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00];

  /// Disc magic: GameCube at 0x1C, Wii at 0x18.
  static const _gcDiscMagic = (0x1C, [0xC2, 0x33, 0x9F, 0x3D]);
  static const _wiiDiscMagic = (0x18, [0x5D, 0x1C, 0x9E, 0xA3]);

  /// ELF machine field (little-endian u16 at 0x12): 0x08 MIPS (PSP),
  /// 0x14 PowerPC (GameCube).
  static const _elfMips = 0x08;
  static const _elfPpc = 0x14;

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
    // WAD: WiiWare container magic "Is" (version follows). Doom IWADs
    // are rejected in [identify] — the only .wad core is GameCube/Wii.
    'wad': [
      (0, [0x49, 0x73]),
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
  Future<bool> validate(String filePath, String extension) async =>
      !(await identify(filePath, extension)).rejected;

  /// Validates [filePath] and identifies the system its content belongs
  /// to, so the importer can pick a core of the *right* system when
  /// several cores claim the extension.
  ///
  /// Returns a [RomIdentity]. When the content is valid but its system
  /// genuinely cannot be told apart (e.g. a plain ISO9660 image that
  /// could be PSX, PSP, GameCube, Saturn or DOS), [RomIdentity.system]
  /// is null and the importer falls back to extension order.
  Future<RomIdentity> identify(String filePath, String extension) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return const RomIdentity(rejectReason: 'File does not exist');
    }

    final stat = await file.stat();
    final size = stat.size;
    if (size == 0) {
      return const RomIdentity(
          rejectReason: 'Not a valid ROM file (content validation failed)');
    }

    final ext = extension.toLowerCase();

    // Read enough of the head to cover every magic offset in the table
    // (ISO9660 PVD at 0x8000, Sega header at 0x7FF0) plus the text
    // sample.
    final bytes = await _readRange(file, 0, size < _headWindow ? size : _headWindow);
    if (bytes.isEmpty) {
      return const RomIdentity(
          rejectReason: 'Not a valid ROM file (content validation failed)');
    }
    final looksText = _isTextFile(bytes);
    const invalid =
        RomIdentity(rejectReason: 'Not a valid ROM file (content validation failed)');

    // Text-by-spec formats: a real cue/playlist/descriptor/launcher IS
    // text — accept it; reject binary impostors (inverse gate).
    if (_textBySpec.contains(ext)) {
      if (size > maxRomSize) return invalid;
      if (!looksText) return invalid;
      if (ext == 'cue') {
        // A cue sheet names its tracks; the track's first sectors carry
        // the disc's system identity (e.g. "SEGA SEGAKATANA" for
        // Dreamcast, "Sony Computer Entertainment" for PSX).
        final system = await _identifyCueSheet(file, bytes);
        return RomIdentity(system: system);
      }
      return const RomIdentity();
    }

    // Size and text gates apply to every binary format.
    if (size < minRomSize || size > maxRomSize || looksText) return invalid;

    // Content identification for ambiguous extensions. Branches that can
    // decide immediately return; the rest record a detected system and
    // fall through to the generic magic table, so a wrong-magic file is
    // still rejected where the format has a reliable signature.
    String? detected;

    switch (ext) {
      case 'wad':
        // WiiWare WAD ("Is" + version). The only .wad core is the
        // GameCube/Wii one — Doom WADs share the extension but are not
        // playable by any catalog core.
        if (_matchesAt(bytes, 0, _wiiWadMagic)) {
          return const RomIdentity(system: 'wii');
        }
        for (final doom in _doomWads) {
          if (_matchesAt(bytes, 0, doom)) {
            return const RomIdentity(
                rejectReason: 'Doom WAD — no core in the catalog can run it');
          }
        }
        return invalid;

      case 'exe':
        if (bytes.length >= 0x40 &&
            bytes[0] == 0x4D &&
            bytes[1] == 0x5A) {
          // "MZ". A PE signature at e_lfanew (0x3C) means a Windows
          // executable — a system binary, not DOS game content.
          final off = bytes[0x3C] |
              (bytes[0x3D] << 8) |
              (bytes[0x3E] << 16) |
              (bytes[0x3F] << 24);
          if (off > 0 &&
              off + 4 <= bytes.length &&
              bytes[off] == 0x50 && // P
              bytes[off + 1] == 0x45 && // E
              bytes[off + 2] == 0x00 &&
              bytes[off + 3] == 0x00) {
            return const RomIdentity(
                rejectReason: 'Windows executable — not playable DOS content');
          }
          return const RomIdentity(system: 'dos');
        }
        return invalid;

      case 'bin':
        // Raw CD track (2352-byte sectors with sync) — a disc fragment,
        // not a game: the descriptor (.cue/.gdi) is the importable file.
        if (size % 2352 == 0 && _matchesAt(bytes, 0, _cdSync)) {
          return const RomIdentity(
              rejectReason:
                  'Raw disc track — import its .cue or .gdi descriptor instead');
        }
        // Cartridges commonly distributed as .bin: identify by header
        // before falling back to the Atari 2600 size heuristic.
        if (_matchesAt(bytes, 0x100, _segaMagic)) {
          return const RomIdentity(system: 'genesis');
        }
        if (_matchesAt(bytes, 0x7FF0, _tmrSegaMagic)) {
          return const RomIdentity(system: 'sms');
        }
        if (_matchesAt(bytes, 0x104, _gbLogo)) {
          final cgb = bytes.length > 0x143 && (bytes[0x143] & 0x80) != 0;
          return RomIdentity(system: cgb ? 'gbc' : 'gb');
        }
        if (_matchesAt(bytes, 0x04, _gbaLogo) || _looksLikeArmHomebrew(bytes)) {
          return const RomIdentity(system: 'gba');
        }
        if (_matchesAt(bytes, 0, _nesMagic)) {
          return const RomIdentity(system: 'nes');
        }
        for (final order in _n64Orders) {
          if (_matchesAt(bytes, 0, order)) {
            return const RomIdentity(system: 'n64');
          }
        }
        // Atari 2600 carts are small powers of two (2K–512K).
        if (size >= 2048 && size <= 512 * 1024 && (size & (size - 1)) == 0) {
          return const RomIdentity(system: 'atari2600');
        }
        return const RomIdentity(
            rejectReason: 'Unrecognized .bin contents — no core can play it');

      case 'zip':
        // PK magic must be present before treating it as an archive.
        if (!_matchesAt(bytes, 0, [0x50, 0x4B, 0x03, 0x04]) &&
            !_matchesAt(bytes, 0, [0x50, 0x4B, 0x05, 0x06])) {
          return invalid;
        }
        return _identifyArchive(file, size);

      case 'nds':
        // NDS files: official logo at 0xC0 for retail dumps; homebrew
        // (devkitARM) instead has the ARM entry branch at 0 plus either
        // the fixed 0x96 or the placeholder game code "####" at 0x0C.
        final armBranch = bytes.length > 3 && bytes[3] == 0xEA;
        if (_matchesAt(bytes, 0xC0, _gbaLogo) ||
            (armBranch &&
                (_looksLikeArmHomebrew(bytes) ||
                    _matchesAt(bytes, 0x0C, _ndsHomebrewCode)))) {
          return const RomIdentity(system: 'nds');
        }
        return invalid;

      case 'gb':
      case 'gbc':
        if (!_matchesAt(bytes, 0x104, _gbLogo)) return invalid;
        final cgb = bytes.length > 0x143 && (bytes[0x143] & 0x80) != 0;
        return RomIdentity(system: cgb ? 'gbc' : 'gb');

      case 'gba':
        if (!_matchesAt(bytes, 0x04, _gbaLogo) &&
            !_looksLikeArmHomebrew(bytes)) {
          return invalid;
        }
        return const RomIdentity(system: 'gba');

      case 'iso':
        // Distinguish the disc systems when a disc magic is present; a
        // bare ISO9660 image stays system-ambiguous and is accepted by
        // the magic table below.
        if (_matchesAt(bytes, _gcDiscMagic.$1, _gcDiscMagic.$2)) {
          return const RomIdentity(system: 'gc');
        }
        if (_matchesAt(bytes, _wiiDiscMagic.$1, _wiiDiscMagic.$2)) {
          return const RomIdentity(system: 'wii');
        }
        break;

      case 'elf':
        if (bytes.length > 0x13) {
          final machine = bytes[0x12] | (bytes[0x13] << 8);
          if (machine == _elfMips) detected = 'psp';
          if (machine == _elfPpc) detected = 'gc';
        }
        break;

      case 'pbp':
        // A PBP holds a PlayStation or PSP executable. PSX eboots embed
        // PSISOIMG/PSTITLEIMG sections; PSP eboots do not.
        if (_containsAscii(bytes, 'PSISOIMG') ||
            _containsAscii(bytes, 'PSTITLEIMG')) {
          detected = 'psx';
        } else {
          detected = 'psp';
        }
        break;

      case 'cue':
        detected = await _identifyCueSheet(file, bytes);
        break;

      case 'com':
      case 'img':
        detected = 'dos';
        break;
      case 'nes':
      case 'unf':
        detected = 'nes';
        break;
      case 'fds':
        detected = 'fds';
        break;
      case 'smc':
      case 'sfc':
        detected = 'snes';
        break;
      case 'md':
      case 'gen':
        detected = 'genesis';
        break;
      case 'sms':
        detected = 'sms';
        break;
      case 'gg':
        detected = 'gg';
        break;
      case 'sg':
        detected = 'sg1000';
        break;
      case 'pce':
      case 'sgx':
        detected = 'pce';
        break;
      case 'a26':
        detected = 'atari2600';
        break;
      case 'n64':
      case 'z64':
      case 'v64':
        detected = 'n64';
        break;
      case 'cdi':
      case 'gdi':
        detected = 'dc';
        break;
      case 'cso':
      case 'prx':
        detected = 'psp';
        break;
      case 'dol':
      case 'gcm':
      case 'ciso':
        detected = 'gc';
        break;
      case 'rvz':
      case 'wbfs':
        detected = 'wii';
        break;
      case 'scummvm':
        detected = 'scumm';
        break;
      case 'fig':
        detected = 'snes';
        break;
    }

    // Foreign-content cross-check: a file whose extension claims one
    // system but whose bytes carry another system's strong signature is
    // mislabeled (a NES ROM renamed .pce, a Genesis ROM renamed .sfc).
    // Without this, headerless formats accept any binary and the wrong
    // core lists the file.
    final expected = detected;
    final foreign = _foreignSystem(bytes);
    if (expected != null &&
        foreign != null &&
        !_sameFamily(expected, foreign)) {
      return RomIdentity(
          rejectReason:
              'Content looks like a $foreign ROM — not .$ext content');
    }

    // Check magic bytes for the extension.
    final magicList = _magicBytes[ext];
    if (magicList == null || magicList.isEmpty) {
      // No magic defined for this extension — accept if binary (the
      // size/text gates above already ran).
      return RomIdentity(system: detected);
    }

    for (final (offset, magic) in magicList) {
      if (_matchesAt(bytes, offset, magic)) {
        return RomIdentity(system: detected);
      }
    }

    // No magic matched. Headerless cart/disc formats (no reliable
    // signature in their spec) stay acceptable as binary — content
    // validation still rejects text/empty/oversized files above.
    return _isHeaderlessFormat(ext)
        ? RomIdentity(system: detected)
        : invalid;
  }

  /// Game Boy header logo at 0x104. The same bytes are shared by GB and
  /// GBC; the CGB flag at 0x143 bit 7 tells them apart.
  static const _gbLogo = [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B];

  /// GBA header logo at 0x04.
  static const _gbaLogo = [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21];

  /// Genesis/Mega Drive header magic at 0x100.
  static const _segaMagic = [0x53, 0x45, 0x47, 0x41]; // "SEGA"

  /// Master System / Game Gear signature at 0x7FF0.
  static const _tmrSegaMagic = [
    0x54, 0x4D, 0x52, 0x20, 0x53, 0x45, 0x47, 0x41, // "TMR SEGA"
  ];

  /// iNES header magic.
  static const _nesMagic = [0x4E, 0x45, 0x53, 0x1A];

  /// N64 byte-order magics (native / little-endian / byte-swapped).
  static const _n64Orders = [
    [0x80, 0x37, 0x12, 0x40],
    [0x40, 0x12, 0x37, 0x80],
    [0x37, 0x80, 0x40, 0x12],
  ];

  /// NDS homebrew placeholder game code (devkitARM default).
  static const _ndsHomebrewCode = [0x23, 0x23, 0x23, 0x23]; // "####"

  /// Homebrew GBA/NDS ROMs built without the official Nintendo logo
  /// still carry the ARM entry branch at 0 and the fixed 0x96 byte at
  /// 0xB2 (0xB0 on some toolchains) — enough to tell them from
  /// arbitrary binaries.
  bool _looksLikeArmHomebrew(List<int> bytes) =>
      bytes.length > 0xB2 &&
      bytes[3] == 0xEA &&
      (bytes[0xB2] == 0x96 || bytes[0xB0] == 0x96);

  /// Extensions inside a zip that identify one console system. Used to
  /// route an archive to the core of the system its contents belong to
  /// instead of the first core that happens to claim `.zip`.
  static const _archiveExtSystems = <String, String>{
    'nes': 'nes', 'fds': 'fds', 'unf': 'nes',
    'gb': 'gb', 'gbc': 'gbc', 'gba': 'gba',
    'smc': 'snes', 'sfc': 'snes',
    'md': 'genesis', 'gen': 'genesis',
    'sms': 'sms', 'gg': 'gg', 'sg': 'sg1000',
    'pce': 'pce', 'sgx': 'pce',
    'a26': 'atari2600',
    'n64': 'n64', 'z64': 'n64', 'v64': 'n64',
    'nds': 'nds',
    'cdi': 'dc', 'gdi': 'dc',
    'pbp': 'psp',
    'dol': 'gc', 'gcm': 'gc',
    'exe': 'dos', 'com': 'dos', 'bat': 'dos',
  };

  /// Entry names that look like arcade ROM chips rather than console
  /// ROMs: numeric chip labels (`sf2.03`, `1941.1a`) or common ROM/keys.
  static final _archChipExt = RegExp(
      r'^(\d{1,3}|bin|rom|key|pal|sram|nv|maincpu|audiocpu|gfx\d*|cod\d*)$');

  /// Reads the central directory of a ZIP archive and decides which
  /// system the archive belongs to from its entry names.
  Future<RomIdentity> _identifyArchive(File file, int size) async {
    // Central directory lives at the end; read the tail.
    const tailWindow = 256 * 1024;
    final start = size > tailWindow ? size - tailWindow : 0;
    final tail = await _readRange(file, start, size);
    final names = _centralDirectoryNames(tail);
    if (names.isEmpty) {
      // PK magic present but the directory is unparseable (truncated or
      // synthetic test archive) — accept without a system claim.
      return const RomIdentity();
    }

    final systems = <String>{};
    var chipLike = false;
    for (final name in names) {
      final dot = name.lastIndexOf('.');
      final e = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
      final system = _archiveExtSystems[e];
      if (system != null) systems.add(system);
      if (_archChipExt.hasMatch(e)) chipLike = true;
    }

    if (systems.length == 1) return RomIdentity(system: systems.first);
    if (systems.length > 1) {
      return const RomIdentity(
          rejectReason:
              'Archive mixes several systems — keep one system per archive');
    }
    if (chipLike) return const RomIdentity(system: 'arcade');
    return const RomIdentity(
        rejectReason: 'Archive holds no recognizable game ROMs');
  }

  /// Extracts entry names from ZIP central directory headers
  /// (`PK\x01\x02`) found in [bytes]. Scanning tolerates leading partial
  /// headers: each signature is read independently.
  List<String> _centralDirectoryNames(List<int> bytes) {
    const sig = [0x50, 0x4B, 0x01, 0x02];
    final out = <String>[];
    for (var i = 0; i + 46 <= bytes.length; i++) {
      if (bytes[i] != sig[0] ||
          bytes[i + 1] != sig[1] ||
          bytes[i + 2] != sig[2] ||
          bytes[i + 3] != sig[3]) {
        continue;
      }
      final nameLen = bytes[i + 28] | (bytes[i + 29] << 8);
      if (nameLen == 0 || nameLen > 512 || i + 46 + nameLen > bytes.length) {
        continue;
      }
      final name = String.fromCharCodes(bytes.sublist(i + 46, i + 46 + nameLen));
      out.add(name);
    }
    return out;
  }

  /// Reads [start, end) fully, in chunks (a single `openRead(...).first`
  /// can return less than requested for larger ranges).
  Future<List<int>> _readRange(File file, int start, int end) async {
    final out = <int>[];
    await for (final chunk in file.openRead(start, end)) {
      out.addAll(chunk);
      if (out.length >= end - start) break;
    }
    return out;
  }

  /// Disc-system markers found in the first sectors of a raw track
  /// (checked in order). Marker -> catalog system id.
  static const _discMarkers = <String, String>{
    'SEGA SEGAKATANA': 'dc', // Dreamcast IP.BIN
    'SEGA SEGASATURN': 'saturn', // Saturn IP.BIN
    'SEGA DISCSYSTEM': 'scd', // Mega-CD header
    'SEGA SEGACD': 'scd',
    'Sony Computer Entertainment': 'psx', // PSX license region
    'PS-X EXE': 'psx', // PSX executable header
    'PC Engine CD-ROM SYSTEM': 'pcecd', // PCE CD IPL
  };

  /// Best-effort system detection for a cue sheet: parse the first
  /// `FILE "..."` line, read the referenced track's head, and look for a
  /// disc-system marker. Returns null when nothing recognizable is found
  /// (the importer then falls back to extension order).
  Future<String?> _identifyCueSheet(File cue, List<int> cueBytes) async {
    final text = String.fromCharCodes(cueBytes);
    final match = RegExp(
      'FILE\\s+(?:"([^"]+)"|(\\S+))',
      caseSensitive: false,
    ).firstMatch(text);
    final ref = match?.group(1) ?? match?.group(2);
    if (ref == null || ref.isEmpty) return null;

    // Track paths in cue sheets are relative to the sheet.
    final dir = cue.parent.path;
    final track = File('$dir${Platform.pathSeparator}$ref');
    final resolved =
        track.existsSync() ? track : File(ref);
    if (!resolved.existsSync()) return null;

    final size = await resolved.length();
    final head = await _readRange(
        resolved, 0, size < 64 * 1024 ? size : 64 * 1024);
    for (final entry in _discMarkers.entries) {
      if (_containsAscii(head, entry.key)) return entry.value;
    }
    return null;
  }

  /// Returns `true` when [needle] (ASCII) appears anywhere in [bytes].
  bool _containsAscii(List<int> bytes, String needle) {
    if (needle.isEmpty || bytes.length < needle.length) return false;
    final first = needle.codeUnitAt(0);
    for (var i = 0; i <= bytes.length - needle.length; i++) {
      if (bytes[i] != first) continue;
      var ok = true;
      for (var j = 1; j < needle.length; j++) {
        if (bytes[i + j] != needle.codeUnitAt(j)) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  /// Returns `true` when [bytes] contain [magic] at [offset].
  bool _matchesAt(List<int> bytes, int offset, List<int> magic) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
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

  /// Returns the system id of the strongest foreign signature in
  /// [bytes], if any. Used to catch mislabeled files (a NES ROM renamed
  /// `.pce`, a Genesis ROM renamed `.sfc`) so the wrong core never lists
  /// them. Only high-confidence signatures live here — 4+ byte magics
  /// with fixed offsets.
  String? _foreignSystem(List<int> bytes) {
    if (_matchesAt(bytes, 0, _nesMagic)) return 'nes';
    if (_matchesAt(bytes, 0x104, _gbLogo)) return 'gb';
    if (_matchesAt(bytes, 0x04, _gbaLogo)) return 'gba';
    if (_matchesAt(bytes, 0x100, _segaMagic)) return 'genesis';
    if (_matchesAt(bytes, 0x7FF0, _tmrSegaMagic)) return 'sms';
    for (final order in _n64Orders) {
      if (_matchesAt(bytes, 0, order)) return 'n64';
    }
    if (_matchesAt(bytes, 0xC0, _gbaLogo)) return 'nds';
    if (_matchesAt(bytes, 0, _dolMagic)) return 'gc';
    if (_matchesAt(bytes, _gcDiscMagic.$1, _gcDiscMagic.$2)) return 'gc';
    if (_matchesAt(bytes, _wiiDiscMagic.$1, _wiiDiscMagic.$2)) return 'wii';
    return null;
  }

  /// Systems that share one core family and must not be treated as
  /// foreign to each other (GameCube/Wii discs; SMS/GG/SG-1000 share
  /// the "TMR SEGA" header and one core).
  static bool _sameFamily(String a, String b) {
    String norm(String s) => switch (s) {
          'gbc' => 'gb',
          'fds' => 'nes',
          'wii' => 'gc',
          'gg' => 'sms',
          'sg1000' => 'sms',
          _ => s,
        };
    return norm(a) == norm(b);
  }

  /// DOL executable magic.
  static const _dolMagic = [0x00, 0xD0, 0x0D, 0xFE];

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
}
