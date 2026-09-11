/// A user-supplied game entry. The app never ships ROMs — every entry
/// references a file the user imported themselves (or a bundled
/// public-domain homebrew sample used as a test fixture).
class GameEntry {
  const GameEntry({
    required this.id,
    required this.title,
    required this.system,
    required this.filePath,
    required this.extension,
    this.fileSize = 0,
    this.sha1 = '',
    this.favorite = false,
    this.coreId = '',
    this.lastPlayedMs = 0,
    this.cheatsOn = 0,
    this.stateCount = 0,
  });

  final String id;
  final String title;
  final String system;
  final String filePath;
  final String extension;
  final int fileSize;
  final String sha1;
  final bool favorite;
  final String coreId;
  final int lastPlayedMs;
  final int cheatsOn;
  final int stateCount;

  GameEntry copyWith({
    bool? favorite,
    String? coreId,
    int? lastPlayedMs,
    int? cheatsOn,
    int? stateCount,
  }) {
    return GameEntry(
      id: id,
      title: title,
      system: system,
      filePath: filePath,
      extension: extension,
      fileSize: fileSize,
      sha1: sha1,
      favorite: favorite ?? this.favorite,
      coreId: coreId ?? this.coreId,
      lastPlayedMs: lastPlayedMs ?? this.lastPlayedMs,
      cheatsOn: cheatsOn ?? this.cheatsOn,
      stateCount: stateCount ?? this.stateCount,
    );
  }
}
