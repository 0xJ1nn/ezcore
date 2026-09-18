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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'system': system,
        'filePath': filePath,
        'extension': extension,
        'fileSize': fileSize,
        'sha1': sha1,
        'favorite': favorite,
        'coreId': coreId,
        'lastPlayedMs': lastPlayedMs,
        'cheatsOn': cheatsOn,
        'stateCount': stateCount,
      };

  factory GameEntry.fromJson(Map<String, dynamic> json) => GameEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        system: json['system'] as String? ?? '',
        filePath: json['filePath'] as String? ?? '',
        extension: json['extension'] as String? ?? '',
        fileSize: json['fileSize'] as int? ?? 0,
        sha1: json['sha1'] as String? ?? '',
        favorite: json['favorite'] as bool? ?? false,
        coreId: json['coreId'] as String? ?? '',
        lastPlayedMs: json['lastPlayedMs'] as int? ?? 0,
        cheatsOn: json['cheatsOn'] as int? ?? 0,
        stateCount: json['stateCount'] as int? ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          system == other.system &&
          filePath == other.filePath &&
          extension == other.extension &&
          fileSize == other.fileSize &&
          sha1 == other.sha1 &&
          favorite == other.favorite &&
          coreId == other.coreId &&
          lastPlayedMs == other.lastPlayedMs &&
          cheatsOn == other.cheatsOn &&
          stateCount == other.stateCount;

  @override
  int get hashCode =>
      Object.hash(id, title, system, filePath, extension, fileSize, sha1,
          favorite, coreId, lastPlayedMs, cheatsOn, stateCount);
}
