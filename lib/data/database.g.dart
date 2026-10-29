// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, Track> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clockMeta = const VerificationMeta('clock');
  @override
  late final GeneratedColumn<String> clock = GeneratedColumn<String>(
    'clock',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originDeviceMeta = const VerificationMeta(
    'originDevice',
  );
  @override
  late final GeneratedColumn<String> originDevice = GeneratedColumn<String>(
    'origin_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ytVideoIdMeta = const VerificationMeta(
    'ytVideoId',
  );
  @override
  late final GeneratedColumn<String> ytVideoId = GeneratedColumn<String>(
    'yt_video_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _artworkRefMeta = const VerificationMeta(
    'artworkRef',
  );
  @override
  late final GeneratedColumn<String> artworkRef = GeneratedColumn<String>(
    'artwork_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileHashMeta = const VerificationMeta(
    'fileHash',
  );
  @override
  late final GeneratedColumn<String> fileHash = GeneratedColumn<String>(
    'file_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _unavailableMeta = const VerificationMeta(
    'unavailable',
  );
  @override
  late final GeneratedColumn<bool> unavailable = GeneratedColumn<bool>(
    'unavailable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("unavailable" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    source,
    ytVideoId,
    title,
    artist,
    album,
    durationMs,
    artworkRef,
    fileHash,
    unavailable,
    searchText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Track> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('clock')) {
      context.handle(
        _clockMeta,
        clock.isAcceptableOrUnknown(data['clock']!, _clockMeta),
      );
    } else if (isInserting) {
      context.missing(_clockMeta);
    }
    if (data.containsKey('origin_device')) {
      context.handle(
        _originDeviceMeta,
        originDevice.isAcceptableOrUnknown(
          data['origin_device']!,
          _originDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_localSeqMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('yt_video_id')) {
      context.handle(
        _ytVideoIdMeta,
        ytVideoId.isAcceptableOrUnknown(data['yt_video_id']!, _ytVideoIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('artwork_ref')) {
      context.handle(
        _artworkRefMeta,
        artworkRef.isAcceptableOrUnknown(data['artwork_ref']!, _artworkRefMeta),
      );
    }
    if (data.containsKey('file_hash')) {
      context.handle(
        _fileHashMeta,
        fileHash.isAcceptableOrUnknown(data['file_hash']!, _fileHashMeta),
      );
    }
    if (data.containsKey('unavailable')) {
      context.handle(
        _unavailableMeta,
        unavailable.isAcceptableOrUnknown(
          data['unavailable']!,
          _unavailableMeta,
        ),
      );
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    } else if (isInserting) {
      context.missing(_searchTextMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Track map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Track(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clock'],
      )!,
      originDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      ytVideoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}yt_video_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      artworkRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_ref'],
      ),
      fileHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_hash'],
      ),
      unavailable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}unavailable'],
      )!,
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      )!,
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class Track extends DataClass implements Insertable<Track> {
  final String id;
  final String clock;
  final String originDevice;
  final bool deleted;
  final int localSeq;

  /// 'yt' | 'local'
  final String source;
  final String? ytVideoId;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String? artworkRef;
  final String? fileHash;
  final bool unavailable;
  final String searchText;
  const Track({
    required this.id,
    required this.clock,
    required this.originDevice,
    required this.deleted,
    required this.localSeq,
    required this.source,
    this.ytVideoId,
    required this.title,
    required this.artist,
    this.album,
    required this.durationMs,
    this.artworkRef,
    this.fileHash,
    required this.unavailable,
    required this.searchText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['clock'] = Variable<String>(clock);
    map['origin_device'] = Variable<String>(originDevice);
    map['deleted'] = Variable<bool>(deleted);
    map['local_seq'] = Variable<int>(localSeq);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || ytVideoId != null) {
      map['yt_video_id'] = Variable<String>(ytVideoId);
    }
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || artworkRef != null) {
      map['artwork_ref'] = Variable<String>(artworkRef);
    }
    if (!nullToAbsent || fileHash != null) {
      map['file_hash'] = Variable<String>(fileHash);
    }
    map['unavailable'] = Variable<bool>(unavailable);
    map['search_text'] = Variable<String>(searchText);
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      clock: Value(clock),
      originDevice: Value(originDevice),
      deleted: Value(deleted),
      localSeq: Value(localSeq),
      source: Value(source),
      ytVideoId: ytVideoId == null && nullToAbsent
          ? const Value.absent()
          : Value(ytVideoId),
      title: Value(title),
      artist: Value(artist),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      durationMs: Value(durationMs),
      artworkRef: artworkRef == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkRef),
      fileHash: fileHash == null && nullToAbsent
          ? const Value.absent()
          : Value(fileHash),
      unavailable: Value(unavailable),
      searchText: Value(searchText),
    );
  }

  factory Track.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Track(
      id: serializer.fromJson<String>(json['id']),
      clock: serializer.fromJson<String>(json['clock']),
      originDevice: serializer.fromJson<String>(json['originDevice']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      localSeq: serializer.fromJson<int>(json['localSeq']),
      source: serializer.fromJson<String>(json['source']),
      ytVideoId: serializer.fromJson<String?>(json['ytVideoId']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      artworkRef: serializer.fromJson<String?>(json['artworkRef']),
      fileHash: serializer.fromJson<String?>(json['fileHash']),
      unavailable: serializer.fromJson<bool>(json['unavailable']),
      searchText: serializer.fromJson<String>(json['searchText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clock': serializer.toJson<String>(clock),
      'originDevice': serializer.toJson<String>(originDevice),
      'deleted': serializer.toJson<bool>(deleted),
      'localSeq': serializer.toJson<int>(localSeq),
      'source': serializer.toJson<String>(source),
      'ytVideoId': serializer.toJson<String?>(ytVideoId),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String?>(album),
      'durationMs': serializer.toJson<int>(durationMs),
      'artworkRef': serializer.toJson<String?>(artworkRef),
      'fileHash': serializer.toJson<String?>(fileHash),
      'unavailable': serializer.toJson<bool>(unavailable),
      'searchText': serializer.toJson<String>(searchText),
    };
  }

  Track copyWith({
    String? id,
    String? clock,
    String? originDevice,
    bool? deleted,
    int? localSeq,
    String? source,
    Value<String?> ytVideoId = const Value.absent(),
    String? title,
    String? artist,
    Value<String?> album = const Value.absent(),
    int? durationMs,
    Value<String?> artworkRef = const Value.absent(),
    Value<String?> fileHash = const Value.absent(),
    bool? unavailable,
    String? searchText,
  }) => Track(
    id: id ?? this.id,
    clock: clock ?? this.clock,
    originDevice: originDevice ?? this.originDevice,
    deleted: deleted ?? this.deleted,
    localSeq: localSeq ?? this.localSeq,
    source: source ?? this.source,
    ytVideoId: ytVideoId.present ? ytVideoId.value : this.ytVideoId,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album.present ? album.value : this.album,
    durationMs: durationMs ?? this.durationMs,
    artworkRef: artworkRef.present ? artworkRef.value : this.artworkRef,
    fileHash: fileHash.present ? fileHash.value : this.fileHash,
    unavailable: unavailable ?? this.unavailable,
    searchText: searchText ?? this.searchText,
  );
  Track copyWithCompanion(TracksCompanion data) {
    return Track(
      id: data.id.present ? data.id.value : this.id,
      clock: data.clock.present ? data.clock.value : this.clock,
      originDevice: data.originDevice.present
          ? data.originDevice.value
          : this.originDevice,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      source: data.source.present ? data.source.value : this.source,
      ytVideoId: data.ytVideoId.present ? data.ytVideoId.value : this.ytVideoId,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      artworkRef: data.artworkRef.present
          ? data.artworkRef.value
          : this.artworkRef,
      fileHash: data.fileHash.present ? data.fileHash.value : this.fileHash,
      unavailable: data.unavailable.present
          ? data.unavailable.value
          : this.unavailable,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Track(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('source: $source, ')
          ..write('ytVideoId: $ytVideoId, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('artworkRef: $artworkRef, ')
          ..write('fileHash: $fileHash, ')
          ..write('unavailable: $unavailable, ')
          ..write('searchText: $searchText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    source,
    ytVideoId,
    title,
    artist,
    album,
    durationMs,
    artworkRef,
    fileHash,
    unavailable,
    searchText,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track &&
          other.id == this.id &&
          other.clock == this.clock &&
          other.originDevice == this.originDevice &&
          other.deleted == this.deleted &&
          other.localSeq == this.localSeq &&
          other.source == this.source &&
          other.ytVideoId == this.ytVideoId &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.durationMs == this.durationMs &&
          other.artworkRef == this.artworkRef &&
          other.fileHash == this.fileHash &&
          other.unavailable == this.unavailable &&
          other.searchText == this.searchText);
}

class TracksCompanion extends UpdateCompanion<Track> {
  final Value<String> id;
  final Value<String> clock;
  final Value<String> originDevice;
  final Value<bool> deleted;
  final Value<int> localSeq;
  final Value<String> source;
  final Value<String?> ytVideoId;
  final Value<String> title;
  final Value<String> artist;
  final Value<String?> album;
  final Value<int> durationMs;
  final Value<String?> artworkRef;
  final Value<String?> fileHash;
  final Value<bool> unavailable;
  final Value<String> searchText;
  final Value<int> rowid;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.clock = const Value.absent(),
    this.originDevice = const Value.absent(),
    this.deleted = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.source = const Value.absent(),
    this.ytVideoId = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.artworkRef = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.unavailable = const Value.absent(),
    this.searchText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TracksCompanion.insert({
    required String id,
    required String clock,
    required String originDevice,
    this.deleted = const Value.absent(),
    required int localSeq,
    required String source,
    this.ytVideoId = const Value.absent(),
    required String title,
    required String artist,
    this.album = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.artworkRef = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.unavailable = const Value.absent(),
    required String searchText,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clock = Value(clock),
       originDevice = Value(originDevice),
       localSeq = Value(localSeq),
       source = Value(source),
       title = Value(title),
       artist = Value(artist),
       searchText = Value(searchText);
  static Insertable<Track> custom({
    Expression<String>? id,
    Expression<String>? clock,
    Expression<String>? originDevice,
    Expression<bool>? deleted,
    Expression<int>? localSeq,
    Expression<String>? source,
    Expression<String>? ytVideoId,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<int>? durationMs,
    Expression<String>? artworkRef,
    Expression<String>? fileHash,
    Expression<bool>? unavailable,
    Expression<String>? searchText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clock != null) 'clock': clock,
      if (originDevice != null) 'origin_device': originDevice,
      if (deleted != null) 'deleted': deleted,
      if (localSeq != null) 'local_seq': localSeq,
      if (source != null) 'source': source,
      if (ytVideoId != null) 'yt_video_id': ytVideoId,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (durationMs != null) 'duration_ms': durationMs,
      if (artworkRef != null) 'artwork_ref': artworkRef,
      if (fileHash != null) 'file_hash': fileHash,
      if (unavailable != null) 'unavailable': unavailable,
      if (searchText != null) 'search_text': searchText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TracksCompanion copyWith({
    Value<String>? id,
    Value<String>? clock,
    Value<String>? originDevice,
    Value<bool>? deleted,
    Value<int>? localSeq,
    Value<String>? source,
    Value<String?>? ytVideoId,
    Value<String>? title,
    Value<String>? artist,
    Value<String?>? album,
    Value<int>? durationMs,
    Value<String?>? artworkRef,
    Value<String?>? fileHash,
    Value<bool>? unavailable,
    Value<String>? searchText,
    Value<int>? rowid,
  }) {
    return TracksCompanion(
      id: id ?? this.id,
      clock: clock ?? this.clock,
      originDevice: originDevice ?? this.originDevice,
      deleted: deleted ?? this.deleted,
      localSeq: localSeq ?? this.localSeq,
      source: source ?? this.source,
      ytVideoId: ytVideoId ?? this.ytVideoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      artworkRef: artworkRef ?? this.artworkRef,
      fileHash: fileHash ?? this.fileHash,
      unavailable: unavailable ?? this.unavailable,
      searchText: searchText ?? this.searchText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clock.present) {
      map['clock'] = Variable<String>(clock.value);
    }
    if (originDevice.present) {
      map['origin_device'] = Variable<String>(originDevice.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (ytVideoId.present) {
      map['yt_video_id'] = Variable<String>(ytVideoId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (artworkRef.present) {
      map['artwork_ref'] = Variable<String>(artworkRef.value);
    }
    if (fileHash.present) {
      map['file_hash'] = Variable<String>(fileHash.value);
    }
    if (unavailable.present) {
      map['unavailable'] = Variable<bool>(unavailable.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('source: $source, ')
          ..write('ytVideoId: $ytVideoId, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationMs: $durationMs, ')
          ..write('artworkRef: $artworkRef, ')
          ..write('fileHash: $fileHash, ')
          ..write('unavailable: $unavailable, ')
          ..write('searchText: $searchText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, Playlist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clockMeta = const VerificationMeta('clock');
  @override
  late final GeneratedColumn<String> clock = GeneratedColumn<String>(
    'clock',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originDeviceMeta = const VerificationMeta(
    'originDevice',
  );
  @override
  late final GeneratedColumn<String> originDevice = GeneratedColumn<String>(
    'origin_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverRefMeta = const VerificationMeta(
    'coverRef',
  );
  @override
  late final GeneratedColumn<String> coverRef = GeneratedColumn<String>(
    'cover_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ytPlaylistUrlMeta = const VerificationMeta(
    'ytPlaylistUrl',
  );
  @override
  late final GeneratedColumn<String> ytPlaylistUrl = GeneratedColumn<String>(
    'yt_playlist_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastYtSyncAtMeta = const VerificationMeta(
    'lastYtSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastYtSyncAt = GeneratedColumn<DateTime>(
    'last_yt_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    name,
    coverRef,
    source,
    ytPlaylistUrl,
    lastYtSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Playlist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('clock')) {
      context.handle(
        _clockMeta,
        clock.isAcceptableOrUnknown(data['clock']!, _clockMeta),
      );
    } else if (isInserting) {
      context.missing(_clockMeta);
    }
    if (data.containsKey('origin_device')) {
      context.handle(
        _originDeviceMeta,
        originDevice.isAcceptableOrUnknown(
          data['origin_device']!,
          _originDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_localSeqMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('cover_ref')) {
      context.handle(
        _coverRefMeta,
        coverRef.isAcceptableOrUnknown(data['cover_ref']!, _coverRefMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('yt_playlist_url')) {
      context.handle(
        _ytPlaylistUrlMeta,
        ytPlaylistUrl.isAcceptableOrUnknown(
          data['yt_playlist_url']!,
          _ytPlaylistUrlMeta,
        ),
      );
    }
    if (data.containsKey('last_yt_sync_at')) {
      context.handle(
        _lastYtSyncAtMeta,
        lastYtSyncAt.isAcceptableOrUnknown(
          data['last_yt_sync_at']!,
          _lastYtSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Playlist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Playlist(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clock'],
      )!,
      originDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      coverRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_ref'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      ytPlaylistUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}yt_playlist_url'],
      ),
      lastYtSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_yt_sync_at'],
      ),
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class Playlist extends DataClass implements Insertable<Playlist> {
  final String id;
  final String clock;
  final String originDevice;
  final bool deleted;
  final int localSeq;
  final String name;
  final String? coverRef;

  /// 'local' | 'yt'
  final String source;
  final String? ytPlaylistUrl;
  final DateTime? lastYtSyncAt;
  const Playlist({
    required this.id,
    required this.clock,
    required this.originDevice,
    required this.deleted,
    required this.localSeq,
    required this.name,
    this.coverRef,
    required this.source,
    this.ytPlaylistUrl,
    this.lastYtSyncAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['clock'] = Variable<String>(clock);
    map['origin_device'] = Variable<String>(originDevice);
    map['deleted'] = Variable<bool>(deleted);
    map['local_seq'] = Variable<int>(localSeq);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || coverRef != null) {
      map['cover_ref'] = Variable<String>(coverRef);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || ytPlaylistUrl != null) {
      map['yt_playlist_url'] = Variable<String>(ytPlaylistUrl);
    }
    if (!nullToAbsent || lastYtSyncAt != null) {
      map['last_yt_sync_at'] = Variable<DateTime>(lastYtSyncAt);
    }
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      clock: Value(clock),
      originDevice: Value(originDevice),
      deleted: Value(deleted),
      localSeq: Value(localSeq),
      name: Value(name),
      coverRef: coverRef == null && nullToAbsent
          ? const Value.absent()
          : Value(coverRef),
      source: Value(source),
      ytPlaylistUrl: ytPlaylistUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(ytPlaylistUrl),
      lastYtSyncAt: lastYtSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastYtSyncAt),
    );
  }

  factory Playlist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Playlist(
      id: serializer.fromJson<String>(json['id']),
      clock: serializer.fromJson<String>(json['clock']),
      originDevice: serializer.fromJson<String>(json['originDevice']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      localSeq: serializer.fromJson<int>(json['localSeq']),
      name: serializer.fromJson<String>(json['name']),
      coverRef: serializer.fromJson<String?>(json['coverRef']),
      source: serializer.fromJson<String>(json['source']),
      ytPlaylistUrl: serializer.fromJson<String?>(json['ytPlaylistUrl']),
      lastYtSyncAt: serializer.fromJson<DateTime?>(json['lastYtSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clock': serializer.toJson<String>(clock),
      'originDevice': serializer.toJson<String>(originDevice),
      'deleted': serializer.toJson<bool>(deleted),
      'localSeq': serializer.toJson<int>(localSeq),
      'name': serializer.toJson<String>(name),
      'coverRef': serializer.toJson<String?>(coverRef),
      'source': serializer.toJson<String>(source),
      'ytPlaylistUrl': serializer.toJson<String?>(ytPlaylistUrl),
      'lastYtSyncAt': serializer.toJson<DateTime?>(lastYtSyncAt),
    };
  }

  Playlist copyWith({
    String? id,
    String? clock,
    String? originDevice,
    bool? deleted,
    int? localSeq,
    String? name,
    Value<String?> coverRef = const Value.absent(),
    String? source,
    Value<String?> ytPlaylistUrl = const Value.absent(),
    Value<DateTime?> lastYtSyncAt = const Value.absent(),
  }) => Playlist(
    id: id ?? this.id,
    clock: clock ?? this.clock,
    originDevice: originDevice ?? this.originDevice,
    deleted: deleted ?? this.deleted,
    localSeq: localSeq ?? this.localSeq,
    name: name ?? this.name,
    coverRef: coverRef.present ? coverRef.value : this.coverRef,
    source: source ?? this.source,
    ytPlaylistUrl: ytPlaylistUrl.present
        ? ytPlaylistUrl.value
        : this.ytPlaylistUrl,
    lastYtSyncAt: lastYtSyncAt.present ? lastYtSyncAt.value : this.lastYtSyncAt,
  );
  Playlist copyWithCompanion(PlaylistsCompanion data) {
    return Playlist(
      id: data.id.present ? data.id.value : this.id,
      clock: data.clock.present ? data.clock.value : this.clock,
      originDevice: data.originDevice.present
          ? data.originDevice.value
          : this.originDevice,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      name: data.name.present ? data.name.value : this.name,
      coverRef: data.coverRef.present ? data.coverRef.value : this.coverRef,
      source: data.source.present ? data.source.value : this.source,
      ytPlaylistUrl: data.ytPlaylistUrl.present
          ? data.ytPlaylistUrl.value
          : this.ytPlaylistUrl,
      lastYtSyncAt: data.lastYtSyncAt.present
          ? data.lastYtSyncAt.value
          : this.lastYtSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Playlist(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('name: $name, ')
          ..write('coverRef: $coverRef, ')
          ..write('source: $source, ')
          ..write('ytPlaylistUrl: $ytPlaylistUrl, ')
          ..write('lastYtSyncAt: $lastYtSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    name,
    coverRef,
    source,
    ytPlaylistUrl,
    lastYtSyncAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Playlist &&
          other.id == this.id &&
          other.clock == this.clock &&
          other.originDevice == this.originDevice &&
          other.deleted == this.deleted &&
          other.localSeq == this.localSeq &&
          other.name == this.name &&
          other.coverRef == this.coverRef &&
          other.source == this.source &&
          other.ytPlaylistUrl == this.ytPlaylistUrl &&
          other.lastYtSyncAt == this.lastYtSyncAt);
}

class PlaylistsCompanion extends UpdateCompanion<Playlist> {
  final Value<String> id;
  final Value<String> clock;
  final Value<String> originDevice;
  final Value<bool> deleted;
  final Value<int> localSeq;
  final Value<String> name;
  final Value<String?> coverRef;
  final Value<String> source;
  final Value<String?> ytPlaylistUrl;
  final Value<DateTime?> lastYtSyncAt;
  final Value<int> rowid;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.clock = const Value.absent(),
    this.originDevice = const Value.absent(),
    this.deleted = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.name = const Value.absent(),
    this.coverRef = const Value.absent(),
    this.source = const Value.absent(),
    this.ytPlaylistUrl = const Value.absent(),
    this.lastYtSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    required String id,
    required String clock,
    required String originDevice,
    this.deleted = const Value.absent(),
    required int localSeq,
    required String name,
    this.coverRef = const Value.absent(),
    required String source,
    this.ytPlaylistUrl = const Value.absent(),
    this.lastYtSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clock = Value(clock),
       originDevice = Value(originDevice),
       localSeq = Value(localSeq),
       name = Value(name),
       source = Value(source);
  static Insertable<Playlist> custom({
    Expression<String>? id,
    Expression<String>? clock,
    Expression<String>? originDevice,
    Expression<bool>? deleted,
    Expression<int>? localSeq,
    Expression<String>? name,
    Expression<String>? coverRef,
    Expression<String>? source,
    Expression<String>? ytPlaylistUrl,
    Expression<DateTime>? lastYtSyncAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clock != null) 'clock': clock,
      if (originDevice != null) 'origin_device': originDevice,
      if (deleted != null) 'deleted': deleted,
      if (localSeq != null) 'local_seq': localSeq,
      if (name != null) 'name': name,
      if (coverRef != null) 'cover_ref': coverRef,
      if (source != null) 'source': source,
      if (ytPlaylistUrl != null) 'yt_playlist_url': ytPlaylistUrl,
      if (lastYtSyncAt != null) 'last_yt_sync_at': lastYtSyncAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? id,
    Value<String>? clock,
    Value<String>? originDevice,
    Value<bool>? deleted,
    Value<int>? localSeq,
    Value<String>? name,
    Value<String?>? coverRef,
    Value<String>? source,
    Value<String?>? ytPlaylistUrl,
    Value<DateTime?>? lastYtSyncAt,
    Value<int>? rowid,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      clock: clock ?? this.clock,
      originDevice: originDevice ?? this.originDevice,
      deleted: deleted ?? this.deleted,
      localSeq: localSeq ?? this.localSeq,
      name: name ?? this.name,
      coverRef: coverRef ?? this.coverRef,
      source: source ?? this.source,
      ytPlaylistUrl: ytPlaylistUrl ?? this.ytPlaylistUrl,
      lastYtSyncAt: lastYtSyncAt ?? this.lastYtSyncAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clock.present) {
      map['clock'] = Variable<String>(clock.value);
    }
    if (originDevice.present) {
      map['origin_device'] = Variable<String>(originDevice.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (coverRef.present) {
      map['cover_ref'] = Variable<String>(coverRef.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (ytPlaylistUrl.present) {
      map['yt_playlist_url'] = Variable<String>(ytPlaylistUrl.value);
    }
    if (lastYtSyncAt.present) {
      map['last_yt_sync_at'] = Variable<DateTime>(lastYtSyncAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('name: $name, ')
          ..write('coverRef: $coverRef, ')
          ..write('source: $source, ')
          ..write('ytPlaylistUrl: $ytPlaylistUrl, ')
          ..write('lastYtSyncAt: $lastYtSyncAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistEntriesTable extends PlaylistEntries
    with TableInfo<$PlaylistEntriesTable, PlaylistEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clockMeta = const VerificationMeta('clock');
  @override
  late final GeneratedColumn<String> clock = GeneratedColumn<String>(
    'clock',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originDeviceMeta = const VerificationMeta(
    'originDevice',
  );
  @override
  late final GeneratedColumn<String> originDevice = GeneratedColumn<String>(
    'origin_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<String> position = GeneratedColumn<String>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _keptMeta = const VerificationMeta('kept');
  @override
  late final GeneratedColumn<bool> kept = GeneratedColumn<bool>(
    'kept',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("kept" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    playlistId,
    trackId,
    position,
    status,
    kept,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('clock')) {
      context.handle(
        _clockMeta,
        clock.isAcceptableOrUnknown(data['clock']!, _clockMeta),
      );
    } else if (isInserting) {
      context.missing(_clockMeta);
    }
    if (data.containsKey('origin_device')) {
      context.handle(
        _originDeviceMeta,
        originDevice.isAcceptableOrUnknown(
          data['origin_device']!,
          _originDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_localSeqMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('kept')) {
      context.handle(
        _keptMeta,
        kept.isAcceptableOrUnknown(data['kept']!, _keptMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clock'],
      )!,
      originDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}position'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      kept: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}kept'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $PlaylistEntriesTable createAlias(String alias) {
    return $PlaylistEntriesTable(attachedDatabase, alias);
  }
}

class PlaylistEntry extends DataClass implements Insertable<PlaylistEntry> {
  final String id;
  final String clock;
  final String originDevice;
  final bool deleted;
  final int localSeq;
  final String playlistId;
  final String trackId;

  /// Fractional index; entries sort by this string.
  final String position;
  final String status;
  final bool kept;
  final DateTime addedAt;
  const PlaylistEntry({
    required this.id,
    required this.clock,
    required this.originDevice,
    required this.deleted,
    required this.localSeq,
    required this.playlistId,
    required this.trackId,
    required this.position,
    required this.status,
    required this.kept,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['clock'] = Variable<String>(clock);
    map['origin_device'] = Variable<String>(originDevice);
    map['deleted'] = Variable<bool>(deleted);
    map['local_seq'] = Variable<int>(localSeq);
    map['playlist_id'] = Variable<String>(playlistId);
    map['track_id'] = Variable<String>(trackId);
    map['position'] = Variable<String>(position);
    map['status'] = Variable<String>(status);
    map['kept'] = Variable<bool>(kept);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  PlaylistEntriesCompanion toCompanion(bool nullToAbsent) {
    return PlaylistEntriesCompanion(
      id: Value(id),
      clock: Value(clock),
      originDevice: Value(originDevice),
      deleted: Value(deleted),
      localSeq: Value(localSeq),
      playlistId: Value(playlistId),
      trackId: Value(trackId),
      position: Value(position),
      status: Value(status),
      kept: Value(kept),
      addedAt: Value(addedAt),
    );
  }

  factory PlaylistEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistEntry(
      id: serializer.fromJson<String>(json['id']),
      clock: serializer.fromJson<String>(json['clock']),
      originDevice: serializer.fromJson<String>(json['originDevice']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      localSeq: serializer.fromJson<int>(json['localSeq']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      trackId: serializer.fromJson<String>(json['trackId']),
      position: serializer.fromJson<String>(json['position']),
      status: serializer.fromJson<String>(json['status']),
      kept: serializer.fromJson<bool>(json['kept']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clock': serializer.toJson<String>(clock),
      'originDevice': serializer.toJson<String>(originDevice),
      'deleted': serializer.toJson<bool>(deleted),
      'localSeq': serializer.toJson<int>(localSeq),
      'playlistId': serializer.toJson<String>(playlistId),
      'trackId': serializer.toJson<String>(trackId),
      'position': serializer.toJson<String>(position),
      'status': serializer.toJson<String>(status),
      'kept': serializer.toJson<bool>(kept),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  PlaylistEntry copyWith({
    String? id,
    String? clock,
    String? originDevice,
    bool? deleted,
    int? localSeq,
    String? playlistId,
    String? trackId,
    String? position,
    String? status,
    bool? kept,
    DateTime? addedAt,
  }) => PlaylistEntry(
    id: id ?? this.id,
    clock: clock ?? this.clock,
    originDevice: originDevice ?? this.originDevice,
    deleted: deleted ?? this.deleted,
    localSeq: localSeq ?? this.localSeq,
    playlistId: playlistId ?? this.playlistId,
    trackId: trackId ?? this.trackId,
    position: position ?? this.position,
    status: status ?? this.status,
    kept: kept ?? this.kept,
    addedAt: addedAt ?? this.addedAt,
  );
  PlaylistEntry copyWithCompanion(PlaylistEntriesCompanion data) {
    return PlaylistEntry(
      id: data.id.present ? data.id.value : this.id,
      clock: data.clock.present ? data.clock.value : this.clock,
      originDevice: data.originDevice.present
          ? data.originDevice.value
          : this.originDevice,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      position: data.position.present ? data.position.value : this.position,
      status: data.status.present ? data.status.value : this.status,
      kept: data.kept.present ? data.kept.value : this.kept,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntry(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('playlistId: $playlistId, ')
          ..write('trackId: $trackId, ')
          ..write('position: $position, ')
          ..write('status: $status, ')
          ..write('kept: $kept, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    playlistId,
    trackId,
    position,
    status,
    kept,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistEntry &&
          other.id == this.id &&
          other.clock == this.clock &&
          other.originDevice == this.originDevice &&
          other.deleted == this.deleted &&
          other.localSeq == this.localSeq &&
          other.playlistId == this.playlistId &&
          other.trackId == this.trackId &&
          other.position == this.position &&
          other.status == this.status &&
          other.kept == this.kept &&
          other.addedAt == this.addedAt);
}

class PlaylistEntriesCompanion extends UpdateCompanion<PlaylistEntry> {
  final Value<String> id;
  final Value<String> clock;
  final Value<String> originDevice;
  final Value<bool> deleted;
  final Value<int> localSeq;
  final Value<String> playlistId;
  final Value<String> trackId;
  final Value<String> position;
  final Value<String> status;
  final Value<bool> kept;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const PlaylistEntriesCompanion({
    this.id = const Value.absent(),
    this.clock = const Value.absent(),
    this.originDevice = const Value.absent(),
    this.deleted = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.trackId = const Value.absent(),
    this.position = const Value.absent(),
    this.status = const Value.absent(),
    this.kept = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistEntriesCompanion.insert({
    required String id,
    required String clock,
    required String originDevice,
    this.deleted = const Value.absent(),
    required int localSeq,
    required String playlistId,
    required String trackId,
    required String position,
    this.status = const Value.absent(),
    this.kept = const Value.absent(),
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clock = Value(clock),
       originDevice = Value(originDevice),
       localSeq = Value(localSeq),
       playlistId = Value(playlistId),
       trackId = Value(trackId),
       position = Value(position),
       addedAt = Value(addedAt);
  static Insertable<PlaylistEntry> custom({
    Expression<String>? id,
    Expression<String>? clock,
    Expression<String>? originDevice,
    Expression<bool>? deleted,
    Expression<int>? localSeq,
    Expression<String>? playlistId,
    Expression<String>? trackId,
    Expression<String>? position,
    Expression<String>? status,
    Expression<bool>? kept,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clock != null) 'clock': clock,
      if (originDevice != null) 'origin_device': originDevice,
      if (deleted != null) 'deleted': deleted,
      if (localSeq != null) 'local_seq': localSeq,
      if (playlistId != null) 'playlist_id': playlistId,
      if (trackId != null) 'track_id': trackId,
      if (position != null) 'position': position,
      if (status != null) 'status': status,
      if (kept != null) 'kept': kept,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? clock,
    Value<String>? originDevice,
    Value<bool>? deleted,
    Value<int>? localSeq,
    Value<String>? playlistId,
    Value<String>? trackId,
    Value<String>? position,
    Value<String>? status,
    Value<bool>? kept,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return PlaylistEntriesCompanion(
      id: id ?? this.id,
      clock: clock ?? this.clock,
      originDevice: originDevice ?? this.originDevice,
      deleted: deleted ?? this.deleted,
      localSeq: localSeq ?? this.localSeq,
      playlistId: playlistId ?? this.playlistId,
      trackId: trackId ?? this.trackId,
      position: position ?? this.position,
      status: status ?? this.status,
      kept: kept ?? this.kept,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clock.present) {
      map['clock'] = Variable<String>(clock.value);
    }
    if (originDevice.present) {
      map['origin_device'] = Variable<String>(originDevice.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (position.present) {
      map['position'] = Variable<String>(position.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (kept.present) {
      map['kept'] = Variable<bool>(kept.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntriesCompanion(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('playlistId: $playlistId, ')
          ..write('trackId: $trackId, ')
          ..write('position: $position, ')
          ..write('status: $status, ')
          ..write('kept: $kept, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $YtSeenTable extends YtSeen with TableInfo<$YtSeenTable, YtSeenData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $YtSeenTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clockMeta = const VerificationMeta('clock');
  @override
  late final GeneratedColumn<String> clock = GeneratedColumn<String>(
    'clock',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originDeviceMeta = const VerificationMeta(
    'originDevice',
  );
  @override
  late final GeneratedColumn<String> originDevice = GeneratedColumn<String>(
    'origin_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _videoIdMeta = const VerificationMeta(
    'videoId',
  );
  @override
  late final GeneratedColumn<String> videoId = GeneratedColumn<String>(
    'video_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    playlistId,
    videoId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'yt_seen';
  @override
  VerificationContext validateIntegrity(
    Insertable<YtSeenData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('clock')) {
      context.handle(
        _clockMeta,
        clock.isAcceptableOrUnknown(data['clock']!, _clockMeta),
      );
    } else if (isInserting) {
      context.missing(_clockMeta);
    }
    if (data.containsKey('origin_device')) {
      context.handle(
        _originDeviceMeta,
        originDevice.isAcceptableOrUnknown(
          data['origin_device']!,
          _originDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_localSeqMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('video_id')) {
      context.handle(
        _videoIdMeta,
        videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {playlistId, videoId},
  ];
  @override
  YtSeenData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return YtSeenData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clock'],
      )!,
      originDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      videoId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_id'],
      )!,
    );
  }

  @override
  $YtSeenTable createAlias(String alias) {
    return $YtSeenTable(attachedDatabase, alias);
  }
}

class YtSeenData extends DataClass implements Insertable<YtSeenData> {
  final String id;
  final String clock;
  final String originDevice;
  final bool deleted;
  final int localSeq;
  final String playlistId;
  final String videoId;
  const YtSeenData({
    required this.id,
    required this.clock,
    required this.originDevice,
    required this.deleted,
    required this.localSeq,
    required this.playlistId,
    required this.videoId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['clock'] = Variable<String>(clock);
    map['origin_device'] = Variable<String>(originDevice);
    map['deleted'] = Variable<bool>(deleted);
    map['local_seq'] = Variable<int>(localSeq);
    map['playlist_id'] = Variable<String>(playlistId);
    map['video_id'] = Variable<String>(videoId);
    return map;
  }

  YtSeenCompanion toCompanion(bool nullToAbsent) {
    return YtSeenCompanion(
      id: Value(id),
      clock: Value(clock),
      originDevice: Value(originDevice),
      deleted: Value(deleted),
      localSeq: Value(localSeq),
      playlistId: Value(playlistId),
      videoId: Value(videoId),
    );
  }

  factory YtSeenData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return YtSeenData(
      id: serializer.fromJson<String>(json['id']),
      clock: serializer.fromJson<String>(json['clock']),
      originDevice: serializer.fromJson<String>(json['originDevice']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      localSeq: serializer.fromJson<int>(json['localSeq']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      videoId: serializer.fromJson<String>(json['videoId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clock': serializer.toJson<String>(clock),
      'originDevice': serializer.toJson<String>(originDevice),
      'deleted': serializer.toJson<bool>(deleted),
      'localSeq': serializer.toJson<int>(localSeq),
      'playlistId': serializer.toJson<String>(playlistId),
      'videoId': serializer.toJson<String>(videoId),
    };
  }

  YtSeenData copyWith({
    String? id,
    String? clock,
    String? originDevice,
    bool? deleted,
    int? localSeq,
    String? playlistId,
    String? videoId,
  }) => YtSeenData(
    id: id ?? this.id,
    clock: clock ?? this.clock,
    originDevice: originDevice ?? this.originDevice,
    deleted: deleted ?? this.deleted,
    localSeq: localSeq ?? this.localSeq,
    playlistId: playlistId ?? this.playlistId,
    videoId: videoId ?? this.videoId,
  );
  YtSeenData copyWithCompanion(YtSeenCompanion data) {
    return YtSeenData(
      id: data.id.present ? data.id.value : this.id,
      clock: data.clock.present ? data.clock.value : this.clock,
      originDevice: data.originDevice.present
          ? data.originDevice.value
          : this.originDevice,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('YtSeenData(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('playlistId: $playlistId, ')
          ..write('videoId: $videoId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    playlistId,
    videoId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is YtSeenData &&
          other.id == this.id &&
          other.clock == this.clock &&
          other.originDevice == this.originDevice &&
          other.deleted == this.deleted &&
          other.localSeq == this.localSeq &&
          other.playlistId == this.playlistId &&
          other.videoId == this.videoId);
}

class YtSeenCompanion extends UpdateCompanion<YtSeenData> {
  final Value<String> id;
  final Value<String> clock;
  final Value<String> originDevice;
  final Value<bool> deleted;
  final Value<int> localSeq;
  final Value<String> playlistId;
  final Value<String> videoId;
  final Value<int> rowid;
  const YtSeenCompanion({
    this.id = const Value.absent(),
    this.clock = const Value.absent(),
    this.originDevice = const Value.absent(),
    this.deleted = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.videoId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  YtSeenCompanion.insert({
    required String id,
    required String clock,
    required String originDevice,
    this.deleted = const Value.absent(),
    required int localSeq,
    required String playlistId,
    required String videoId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clock = Value(clock),
       originDevice = Value(originDevice),
       localSeq = Value(localSeq),
       playlistId = Value(playlistId),
       videoId = Value(videoId);
  static Insertable<YtSeenData> custom({
    Expression<String>? id,
    Expression<String>? clock,
    Expression<String>? originDevice,
    Expression<bool>? deleted,
    Expression<int>? localSeq,
    Expression<String>? playlistId,
    Expression<String>? videoId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clock != null) 'clock': clock,
      if (originDevice != null) 'origin_device': originDevice,
      if (deleted != null) 'deleted': deleted,
      if (localSeq != null) 'local_seq': localSeq,
      if (playlistId != null) 'playlist_id': playlistId,
      if (videoId != null) 'video_id': videoId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  YtSeenCompanion copyWith({
    Value<String>? id,
    Value<String>? clock,
    Value<String>? originDevice,
    Value<bool>? deleted,
    Value<int>? localSeq,
    Value<String>? playlistId,
    Value<String>? videoId,
    Value<int>? rowid,
  }) {
    return YtSeenCompanion(
      id: id ?? this.id,
      clock: clock ?? this.clock,
      originDevice: originDevice ?? this.originDevice,
      deleted: deleted ?? this.deleted,
      localSeq: localSeq ?? this.localSeq,
      playlistId: playlistId ?? this.playlistId,
      videoId: videoId ?? this.videoId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clock.present) {
      map['clock'] = Variable<String>(clock.value);
    }
    if (originDevice.present) {
      map['origin_device'] = Variable<String>(originDevice.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (videoId.present) {
      map['video_id'] = Variable<String>(videoId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('YtSeenCompanion(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('playlistId: $playlistId, ')
          ..write('videoId: $videoId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalFilesTable extends LocalFiles
    with TableInfo<$LocalFilesTable, LocalFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mtimeMsMeta = const VerificationMeta(
    'mtimeMs',
  );
  @override
  late final GeneratedColumn<int> mtimeMs = GeneratedColumn<int>(
    'mtime_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requestedAtMeta = const VerificationMeta(
    'requestedAt',
  );
  @override
  late final GeneratedColumn<int> requestedAt = GeneratedColumn<int>(
    'requested_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _manualMeta = const VerificationMeta('manual');
  @override
  late final GeneratedColumn<bool> manual = GeneratedColumn<bool>(
    'manual',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("manual" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    trackId,
    path,
    state,
    bytes,
    mtimeMs,
    error,
    requestedAt,
    manual,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('mtime_ms')) {
      context.handle(
        _mtimeMsMeta,
        mtimeMs.isAcceptableOrUnknown(data['mtime_ms']!, _mtimeMsMeta),
      );
    } else if (isInserting) {
      context.missing(_mtimeMsMeta);
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('requested_at')) {
      context.handle(
        _requestedAtMeta,
        requestedAt.isAcceptableOrUnknown(
          data['requested_at']!,
          _requestedAtMeta,
        ),
      );
    }
    if (data.containsKey('manual')) {
      context.handle(
        _manualMeta,
        manual.isAcceptableOrUnknown(data['manual']!, _manualMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackId};
  @override
  LocalFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFile(
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes'],
      )!,
      mtimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mtime_ms'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      requestedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}requested_at'],
      ),
      manual: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}manual'],
      )!,
    );
  }

  @override
  $LocalFilesTable createAlias(String alias) {
    return $LocalFilesTable(attachedDatabase, alias);
  }
}

class LocalFile extends DataClass implements Insertable<LocalFile> {
  final String trackId;
  final String path;

  /// 'done' | 'missing' | 'queued' | 'downloading' | 'failed'
  final String state;
  final int bytes;
  final int mtimeMs;
  final String? error;

  /// When a YouTube download was requested (ms since epoch); FIFO key.
  final int? requestedAt;

  /// A YouTube download the user asked for on this one track.
  final bool manual;
  const LocalFile({
    required this.trackId,
    required this.path,
    required this.state,
    required this.bytes,
    required this.mtimeMs,
    this.error,
    this.requestedAt,
    required this.manual,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_id'] = Variable<String>(trackId);
    map['path'] = Variable<String>(path);
    map['state'] = Variable<String>(state);
    map['bytes'] = Variable<int>(bytes);
    map['mtime_ms'] = Variable<int>(mtimeMs);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    if (!nullToAbsent || requestedAt != null) {
      map['requested_at'] = Variable<int>(requestedAt);
    }
    map['manual'] = Variable<bool>(manual);
    return map;
  }

  LocalFilesCompanion toCompanion(bool nullToAbsent) {
    return LocalFilesCompanion(
      trackId: Value(trackId),
      path: Value(path),
      state: Value(state),
      bytes: Value(bytes),
      mtimeMs: Value(mtimeMs),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      requestedAt: requestedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(requestedAt),
      manual: Value(manual),
    );
  }

  factory LocalFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFile(
      trackId: serializer.fromJson<String>(json['trackId']),
      path: serializer.fromJson<String>(json['path']),
      state: serializer.fromJson<String>(json['state']),
      bytes: serializer.fromJson<int>(json['bytes']),
      mtimeMs: serializer.fromJson<int>(json['mtimeMs']),
      error: serializer.fromJson<String?>(json['error']),
      requestedAt: serializer.fromJson<int?>(json['requestedAt']),
      manual: serializer.fromJson<bool>(json['manual']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackId': serializer.toJson<String>(trackId),
      'path': serializer.toJson<String>(path),
      'state': serializer.toJson<String>(state),
      'bytes': serializer.toJson<int>(bytes),
      'mtimeMs': serializer.toJson<int>(mtimeMs),
      'error': serializer.toJson<String?>(error),
      'requestedAt': serializer.toJson<int?>(requestedAt),
      'manual': serializer.toJson<bool>(manual),
    };
  }

  LocalFile copyWith({
    String? trackId,
    String? path,
    String? state,
    int? bytes,
    int? mtimeMs,
    Value<String?> error = const Value.absent(),
    Value<int?> requestedAt = const Value.absent(),
    bool? manual,
  }) => LocalFile(
    trackId: trackId ?? this.trackId,
    path: path ?? this.path,
    state: state ?? this.state,
    bytes: bytes ?? this.bytes,
    mtimeMs: mtimeMs ?? this.mtimeMs,
    error: error.present ? error.value : this.error,
    requestedAt: requestedAt.present ? requestedAt.value : this.requestedAt,
    manual: manual ?? this.manual,
  );
  LocalFile copyWithCompanion(LocalFilesCompanion data) {
    return LocalFile(
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      path: data.path.present ? data.path.value : this.path,
      state: data.state.present ? data.state.value : this.state,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      mtimeMs: data.mtimeMs.present ? data.mtimeMs.value : this.mtimeMs,
      error: data.error.present ? data.error.value : this.error,
      requestedAt: data.requestedAt.present
          ? data.requestedAt.value
          : this.requestedAt,
      manual: data.manual.present ? data.manual.value : this.manual,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFile(')
          ..write('trackId: $trackId, ')
          ..write('path: $path, ')
          ..write('state: $state, ')
          ..write('bytes: $bytes, ')
          ..write('mtimeMs: $mtimeMs, ')
          ..write('error: $error, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('manual: $manual')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    trackId,
    path,
    state,
    bytes,
    mtimeMs,
    error,
    requestedAt,
    manual,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFile &&
          other.trackId == this.trackId &&
          other.path == this.path &&
          other.state == this.state &&
          other.bytes == this.bytes &&
          other.mtimeMs == this.mtimeMs &&
          other.error == this.error &&
          other.requestedAt == this.requestedAt &&
          other.manual == this.manual);
}

class LocalFilesCompanion extends UpdateCompanion<LocalFile> {
  final Value<String> trackId;
  final Value<String> path;
  final Value<String> state;
  final Value<int> bytes;
  final Value<int> mtimeMs;
  final Value<String?> error;
  final Value<int?> requestedAt;
  final Value<bool> manual;
  final Value<int> rowid;
  const LocalFilesCompanion({
    this.trackId = const Value.absent(),
    this.path = const Value.absent(),
    this.state = const Value.absent(),
    this.bytes = const Value.absent(),
    this.mtimeMs = const Value.absent(),
    this.error = const Value.absent(),
    this.requestedAt = const Value.absent(),
    this.manual = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFilesCompanion.insert({
    required String trackId,
    required String path,
    required String state,
    required int bytes,
    required int mtimeMs,
    this.error = const Value.absent(),
    this.requestedAt = const Value.absent(),
    this.manual = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : trackId = Value(trackId),
       path = Value(path),
       state = Value(state),
       bytes = Value(bytes),
       mtimeMs = Value(mtimeMs);
  static Insertable<LocalFile> custom({
    Expression<String>? trackId,
    Expression<String>? path,
    Expression<String>? state,
    Expression<int>? bytes,
    Expression<int>? mtimeMs,
    Expression<String>? error,
    Expression<int>? requestedAt,
    Expression<bool>? manual,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackId != null) 'track_id': trackId,
      if (path != null) 'path': path,
      if (state != null) 'state': state,
      if (bytes != null) 'bytes': bytes,
      if (mtimeMs != null) 'mtime_ms': mtimeMs,
      if (error != null) 'error': error,
      if (requestedAt != null) 'requested_at': requestedAt,
      if (manual != null) 'manual': manual,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFilesCompanion copyWith({
    Value<String>? trackId,
    Value<String>? path,
    Value<String>? state,
    Value<int>? bytes,
    Value<int>? mtimeMs,
    Value<String?>? error,
    Value<int?>? requestedAt,
    Value<bool>? manual,
    Value<int>? rowid,
  }) {
    return LocalFilesCompanion(
      trackId: trackId ?? this.trackId,
      path: path ?? this.path,
      state: state ?? this.state,
      bytes: bytes ?? this.bytes,
      mtimeMs: mtimeMs ?? this.mtimeMs,
      error: error ?? this.error,
      requestedAt: requestedAt ?? this.requestedAt,
      manual: manual ?? this.manual,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (mtimeMs.present) {
      map['mtime_ms'] = Variable<int>(mtimeMs.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (requestedAt.present) {
      map['requested_at'] = Variable<int>(requestedAt.value);
    }
    if (manual.present) {
      map['manual'] = Variable<bool>(manual.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFilesCompanion(')
          ..write('trackId: $trackId, ')
          ..write('path: $path, ')
          ..write('state: $state, ')
          ..write('bytes: $bytes, ')
          ..write('mtimeMs: $mtimeMs, ')
          ..write('error: $error, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('manual: $manual, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistDevicePrefsTable extends PlaylistDevicePrefs
    with TableInfo<$PlaylistDevicePrefsTable, PlaylistDevicePref> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistDevicePrefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadEnabledMeta = const VerificationMeta(
    'downloadEnabled',
  );
  @override
  late final GeneratedColumn<bool> downloadEnabled = GeneratedColumn<bool>(
    'download_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("download_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [playlistId, downloadEnabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_device_prefs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistDevicePref> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('download_enabled')) {
      context.handle(
        _downloadEnabledMeta,
        downloadEnabled.isAcceptableOrUnknown(
          data['download_enabled']!,
          _downloadEnabledMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistId};
  @override
  PlaylistDevicePref map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistDevicePref(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      downloadEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}download_enabled'],
      )!,
    );
  }

  @override
  $PlaylistDevicePrefsTable createAlias(String alias) {
    return $PlaylistDevicePrefsTable(attachedDatabase, alias);
  }
}

class PlaylistDevicePref extends DataClass
    implements Insertable<PlaylistDevicePref> {
  final String playlistId;
  final bool downloadEnabled;
  const PlaylistDevicePref({
    required this.playlistId,
    required this.downloadEnabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<String>(playlistId);
    map['download_enabled'] = Variable<bool>(downloadEnabled);
    return map;
  }

  PlaylistDevicePrefsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistDevicePrefsCompanion(
      playlistId: Value(playlistId),
      downloadEnabled: Value(downloadEnabled),
    );
  }

  factory PlaylistDevicePref.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistDevicePref(
      playlistId: serializer.fromJson<String>(json['playlistId']),
      downloadEnabled: serializer.fromJson<bool>(json['downloadEnabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<String>(playlistId),
      'downloadEnabled': serializer.toJson<bool>(downloadEnabled),
    };
  }

  PlaylistDevicePref copyWith({String? playlistId, bool? downloadEnabled}) =>
      PlaylistDevicePref(
        playlistId: playlistId ?? this.playlistId,
        downloadEnabled: downloadEnabled ?? this.downloadEnabled,
      );
  PlaylistDevicePref copyWithCompanion(PlaylistDevicePrefsCompanion data) {
    return PlaylistDevicePref(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      downloadEnabled: data.downloadEnabled.present
          ? data.downloadEnabled.value
          : this.downloadEnabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistDevicePref(')
          ..write('playlistId: $playlistId, ')
          ..write('downloadEnabled: $downloadEnabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(playlistId, downloadEnabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistDevicePref &&
          other.playlistId == this.playlistId &&
          other.downloadEnabled == this.downloadEnabled);
}

class PlaylistDevicePrefsCompanion extends UpdateCompanion<PlaylistDevicePref> {
  final Value<String> playlistId;
  final Value<bool> downloadEnabled;
  final Value<int> rowid;
  const PlaylistDevicePrefsCompanion({
    this.playlistId = const Value.absent(),
    this.downloadEnabled = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistDevicePrefsCompanion.insert({
    required String playlistId,
    this.downloadEnabled = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId);
  static Insertable<PlaylistDevicePref> custom({
    Expression<String>? playlistId,
    Expression<bool>? downloadEnabled,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (downloadEnabled != null) 'download_enabled': downloadEnabled,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistDevicePrefsCompanion copyWith({
    Value<String>? playlistId,
    Value<bool>? downloadEnabled,
    Value<int>? rowid,
  }) {
    return PlaylistDevicePrefsCompanion(
      playlistId: playlistId ?? this.playlistId,
      downloadEnabled: downloadEnabled ?? this.downloadEnabled,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (downloadEnabled.present) {
      map['download_enabled'] = Variable<bool>(downloadEnabled.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistDevicePrefsCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('downloadEnabled: $downloadEnabled, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryFoldersTable extends LibraryFolders
    with TableInfo<$LibraryFoldersTable, LibraryFolder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryFoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastScanAtMeta = const VerificationMeta(
    'lastScanAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastScanAt = GeneratedColumn<DateTime>(
    'last_scan_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [path, lastScanAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryFolder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('last_scan_at')) {
      context.handle(
        _lastScanAtMeta,
        lastScanAt.isAcceptableOrUnknown(
          data['last_scan_at']!,
          _lastScanAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  LibraryFolder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryFolder(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      lastScanAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_scan_at'],
      ),
    );
  }

  @override
  $LibraryFoldersTable createAlias(String alias) {
    return $LibraryFoldersTable(attachedDatabase, alias);
  }
}

class LibraryFolder extends DataClass implements Insertable<LibraryFolder> {
  final String path;
  final DateTime? lastScanAt;
  const LibraryFolder({required this.path, this.lastScanAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || lastScanAt != null) {
      map['last_scan_at'] = Variable<DateTime>(lastScanAt);
    }
    return map;
  }

  LibraryFoldersCompanion toCompanion(bool nullToAbsent) {
    return LibraryFoldersCompanion(
      path: Value(path),
      lastScanAt: lastScanAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastScanAt),
    );
  }

  factory LibraryFolder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryFolder(
      path: serializer.fromJson<String>(json['path']),
      lastScanAt: serializer.fromJson<DateTime?>(json['lastScanAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'lastScanAt': serializer.toJson<DateTime?>(lastScanAt),
    };
  }

  LibraryFolder copyWith({
    String? path,
    Value<DateTime?> lastScanAt = const Value.absent(),
  }) => LibraryFolder(
    path: path ?? this.path,
    lastScanAt: lastScanAt.present ? lastScanAt.value : this.lastScanAt,
  );
  LibraryFolder copyWithCompanion(LibraryFoldersCompanion data) {
    return LibraryFolder(
      path: data.path.present ? data.path.value : this.path,
      lastScanAt: data.lastScanAt.present
          ? data.lastScanAt.value
          : this.lastScanAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFolder(')
          ..write('path: $path, ')
          ..write('lastScanAt: $lastScanAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, lastScanAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryFolder &&
          other.path == this.path &&
          other.lastScanAt == this.lastScanAt);
}

class LibraryFoldersCompanion extends UpdateCompanion<LibraryFolder> {
  final Value<String> path;
  final Value<DateTime?> lastScanAt;
  final Value<int> rowid;
  const LibraryFoldersCompanion({
    this.path = const Value.absent(),
    this.lastScanAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryFoldersCompanion.insert({
    required String path,
    this.lastScanAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path);
  static Insertable<LibraryFolder> custom({
    Expression<String>? path,
    Expression<DateTime>? lastScanAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (lastScanAt != null) 'last_scan_at': lastScanAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryFoldersCompanion copyWith({
    Value<String>? path,
    Value<DateTime?>? lastScanAt,
    Value<int>? rowid,
  }) {
    return LibraryFoldersCompanion(
      path: path ?? this.path,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (lastScanAt.present) {
      map['last_scan_at'] = Variable<DateTime>(lastScanAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFoldersCompanion(')
          ..write('path: $path, ')
          ..write('lastScanAt: $lastScanAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlayHistoryTable extends PlayHistory
    with TableInfo<$PlayHistoryTable, PlayHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playedAtMeta = const VerificationMeta(
    'playedAt',
  );
  @override
  late final GeneratedColumn<DateTime> playedAt = GeneratedColumn<DateTime>(
    'played_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, trackId, playlistId, playedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayHistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    }
    if (data.containsKey('played_at')) {
      context.handle(
        _playedAtMeta,
        playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_playedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlayHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayHistoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      ),
      playedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}played_at'],
      )!,
    );
  }

  @override
  $PlayHistoryTable createAlias(String alias) {
    return $PlayHistoryTable(attachedDatabase, alias);
  }
}

class PlayHistoryEntry extends DataClass
    implements Insertable<PlayHistoryEntry> {
  /// Monotonic, so "newest" never depends on the clock's resolution.
  final int id;
  final String trackId;
  final String? playlistId;
  final DateTime playedAt;
  const PlayHistoryEntry({
    required this.id,
    required this.trackId,
    this.playlistId,
    required this.playedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_id'] = Variable<String>(trackId);
    if (!nullToAbsent || playlistId != null) {
      map['playlist_id'] = Variable<String>(playlistId);
    }
    map['played_at'] = Variable<DateTime>(playedAt);
    return map;
  }

  PlayHistoryCompanion toCompanion(bool nullToAbsent) {
    return PlayHistoryCompanion(
      id: Value(id),
      trackId: Value(trackId),
      playlistId: playlistId == null && nullToAbsent
          ? const Value.absent()
          : Value(playlistId),
      playedAt: Value(playedAt),
    );
  }

  factory PlayHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayHistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      trackId: serializer.fromJson<String>(json['trackId']),
      playlistId: serializer.fromJson<String?>(json['playlistId']),
      playedAt: serializer.fromJson<DateTime>(json['playedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackId': serializer.toJson<String>(trackId),
      'playlistId': serializer.toJson<String?>(playlistId),
      'playedAt': serializer.toJson<DateTime>(playedAt),
    };
  }

  PlayHistoryEntry copyWith({
    int? id,
    String? trackId,
    Value<String?> playlistId = const Value.absent(),
    DateTime? playedAt,
  }) => PlayHistoryEntry(
    id: id ?? this.id,
    trackId: trackId ?? this.trackId,
    playlistId: playlistId.present ? playlistId.value : this.playlistId,
    playedAt: playedAt ?? this.playedAt,
  );
  PlayHistoryEntry copyWithCompanion(PlayHistoryCompanion data) {
    return PlayHistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryEntry(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('playlistId: $playlistId, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, trackId, playlistId, playedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayHistoryEntry &&
          other.id == this.id &&
          other.trackId == this.trackId &&
          other.playlistId == this.playlistId &&
          other.playedAt == this.playedAt);
}

class PlayHistoryCompanion extends UpdateCompanion<PlayHistoryEntry> {
  final Value<int> id;
  final Value<String> trackId;
  final Value<String?> playlistId;
  final Value<DateTime> playedAt;
  const PlayHistoryCompanion({
    this.id = const Value.absent(),
    this.trackId = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.playedAt = const Value.absent(),
  });
  PlayHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String trackId,
    this.playlistId = const Value.absent(),
    required DateTime playedAt,
  }) : trackId = Value(trackId),
       playedAt = Value(playedAt);
  static Insertable<PlayHistoryEntry> custom({
    Expression<int>? id,
    Expression<String>? trackId,
    Expression<String>? playlistId,
    Expression<DateTime>? playedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackId != null) 'track_id': trackId,
      if (playlistId != null) 'playlist_id': playlistId,
      if (playedAt != null) 'played_at': playedAt,
    });
  }

  PlayHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? trackId,
    Value<String?>? playlistId,
    Value<DateTime>? playedAt,
  }) {
    return PlayHistoryCompanion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      playlistId: playlistId ?? this.playlistId,
      playedAt: playedAt ?? this.playedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<DateTime>(playedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryCompanion(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('playlistId: $playlistId, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }
}

class $ThemesTable extends Themes with TableInfo<$ThemesTable, ThemeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThemesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clockMeta = const VerificationMeta('clock');
  @override
  late final GeneratedColumn<String> clock = GeneratedColumn<String>(
    'clock',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originDeviceMeta = const VerificationMeta(
    'originDevice',
  );
  @override
  late final GeneratedColumn<String> originDevice = GeneratedColumn<String>(
    'origin_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _specJsonMeta = const VerificationMeta(
    'specJson',
  );
  @override
  late final GeneratedColumn<String> specJson = GeneratedColumn<String>(
    'spec_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    name,
    specJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'themes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ThemeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('clock')) {
      context.handle(
        _clockMeta,
        clock.isAcceptableOrUnknown(data['clock']!, _clockMeta),
      );
    } else if (isInserting) {
      context.missing(_clockMeta);
    }
    if (data.containsKey('origin_device')) {
      context.handle(
        _originDeviceMeta,
        originDevice.isAcceptableOrUnknown(
          data['origin_device']!,
          _originDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_localSeqMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('spec_json')) {
      context.handle(
        _specJsonMeta,
        specJson.isAcceptableOrUnknown(data['spec_json']!, _specJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_specJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ThemeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThemeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clock'],
      )!,
      originDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      specJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spec_json'],
      )!,
    );
  }

  @override
  $ThemesTable createAlias(String alias) {
    return $ThemesTable(attachedDatabase, alias);
  }
}

class ThemeRow extends DataClass implements Insertable<ThemeRow> {
  final String id;
  final String clock;
  final String originDevice;
  final bool deleted;
  final int localSeq;
  final String name;
  final String specJson;
  const ThemeRow({
    required this.id,
    required this.clock,
    required this.originDevice,
    required this.deleted,
    required this.localSeq,
    required this.name,
    required this.specJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['clock'] = Variable<String>(clock);
    map['origin_device'] = Variable<String>(originDevice);
    map['deleted'] = Variable<bool>(deleted);
    map['local_seq'] = Variable<int>(localSeq);
    map['name'] = Variable<String>(name);
    map['spec_json'] = Variable<String>(specJson);
    return map;
  }

  ThemesCompanion toCompanion(bool nullToAbsent) {
    return ThemesCompanion(
      id: Value(id),
      clock: Value(clock),
      originDevice: Value(originDevice),
      deleted: Value(deleted),
      localSeq: Value(localSeq),
      name: Value(name),
      specJson: Value(specJson),
    );
  }

  factory ThemeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThemeRow(
      id: serializer.fromJson<String>(json['id']),
      clock: serializer.fromJson<String>(json['clock']),
      originDevice: serializer.fromJson<String>(json['originDevice']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      localSeq: serializer.fromJson<int>(json['localSeq']),
      name: serializer.fromJson<String>(json['name']),
      specJson: serializer.fromJson<String>(json['specJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clock': serializer.toJson<String>(clock),
      'originDevice': serializer.toJson<String>(originDevice),
      'deleted': serializer.toJson<bool>(deleted),
      'localSeq': serializer.toJson<int>(localSeq),
      'name': serializer.toJson<String>(name),
      'specJson': serializer.toJson<String>(specJson),
    };
  }

  ThemeRow copyWith({
    String? id,
    String? clock,
    String? originDevice,
    bool? deleted,
    int? localSeq,
    String? name,
    String? specJson,
  }) => ThemeRow(
    id: id ?? this.id,
    clock: clock ?? this.clock,
    originDevice: originDevice ?? this.originDevice,
    deleted: deleted ?? this.deleted,
    localSeq: localSeq ?? this.localSeq,
    name: name ?? this.name,
    specJson: specJson ?? this.specJson,
  );
  ThemeRow copyWithCompanion(ThemesCompanion data) {
    return ThemeRow(
      id: data.id.present ? data.id.value : this.id,
      clock: data.clock.present ? data.clock.value : this.clock,
      originDevice: data.originDevice.present
          ? data.originDevice.value
          : this.originDevice,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      name: data.name.present ? data.name.value : this.name,
      specJson: data.specJson.present ? data.specJson.value : this.specJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThemeRow(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('name: $name, ')
          ..write('specJson: $specJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, clock, originDevice, deleted, localSeq, name, specJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThemeRow &&
          other.id == this.id &&
          other.clock == this.clock &&
          other.originDevice == this.originDevice &&
          other.deleted == this.deleted &&
          other.localSeq == this.localSeq &&
          other.name == this.name &&
          other.specJson == this.specJson);
}

class ThemesCompanion extends UpdateCompanion<ThemeRow> {
  final Value<String> id;
  final Value<String> clock;
  final Value<String> originDevice;
  final Value<bool> deleted;
  final Value<int> localSeq;
  final Value<String> name;
  final Value<String> specJson;
  final Value<int> rowid;
  const ThemesCompanion({
    this.id = const Value.absent(),
    this.clock = const Value.absent(),
    this.originDevice = const Value.absent(),
    this.deleted = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.name = const Value.absent(),
    this.specJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThemesCompanion.insert({
    required String id,
    required String clock,
    required String originDevice,
    this.deleted = const Value.absent(),
    required int localSeq,
    required String name,
    required String specJson,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clock = Value(clock),
       originDevice = Value(originDevice),
       localSeq = Value(localSeq),
       name = Value(name),
       specJson = Value(specJson);
  static Insertable<ThemeRow> custom({
    Expression<String>? id,
    Expression<String>? clock,
    Expression<String>? originDevice,
    Expression<bool>? deleted,
    Expression<int>? localSeq,
    Expression<String>? name,
    Expression<String>? specJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clock != null) 'clock': clock,
      if (originDevice != null) 'origin_device': originDevice,
      if (deleted != null) 'deleted': deleted,
      if (localSeq != null) 'local_seq': localSeq,
      if (name != null) 'name': name,
      if (specJson != null) 'spec_json': specJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThemesCompanion copyWith({
    Value<String>? id,
    Value<String>? clock,
    Value<String>? originDevice,
    Value<bool>? deleted,
    Value<int>? localSeq,
    Value<String>? name,
    Value<String>? specJson,
    Value<int>? rowid,
  }) {
    return ThemesCompanion(
      id: id ?? this.id,
      clock: clock ?? this.clock,
      originDevice: originDevice ?? this.originDevice,
      deleted: deleted ?? this.deleted,
      localSeq: localSeq ?? this.localSeq,
      name: name ?? this.name,
      specJson: specJson ?? this.specJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clock.present) {
      map['clock'] = Variable<String>(clock.value);
    }
    if (originDevice.present) {
      map['origin_device'] = Variable<String>(originDevice.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (specJson.present) {
      map['spec_json'] = Variable<String>(specJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThemesCompanion(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('name: $name, ')
          ..write('specJson: $specJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FontsTable extends Fonts with TableInfo<$FontsTable, FontRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FontsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clockMeta = const VerificationMeta('clock');
  @override
  late final GeneratedColumn<String> clock = GeneratedColumn<String>(
    'clock',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originDeviceMeta = const VerificationMeta(
    'originDevice',
  );
  @override
  late final GeneratedColumn<String> originDevice = GeneratedColumn<String>(
    'origin_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _familyMeta = const VerificationMeta('family');
  @override
  late final GeneratedColumn<String> family = GeneratedColumn<String>(
    'family',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileHashMeta = const VerificationMeta(
    'fileHash',
  );
  @override
  late final GeneratedColumn<String> fileHash = GeneratedColumn<String>(
    'file_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extMeta = const VerificationMeta('ext');
  @override
  late final GeneratedColumn<String> ext = GeneratedColumn<String>(
    'ext',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    family,
    fileHash,
    ext,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fonts';
  @override
  VerificationContext validateIntegrity(
    Insertable<FontRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('clock')) {
      context.handle(
        _clockMeta,
        clock.isAcceptableOrUnknown(data['clock']!, _clockMeta),
      );
    } else if (isInserting) {
      context.missing(_clockMeta);
    }
    if (data.containsKey('origin_device')) {
      context.handle(
        _originDeviceMeta,
        originDevice.isAcceptableOrUnknown(
          data['origin_device']!,
          _originDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_localSeqMeta);
    }
    if (data.containsKey('family')) {
      context.handle(
        _familyMeta,
        family.isAcceptableOrUnknown(data['family']!, _familyMeta),
      );
    } else if (isInserting) {
      context.missing(_familyMeta);
    }
    if (data.containsKey('file_hash')) {
      context.handle(
        _fileHashMeta,
        fileHash.isAcceptableOrUnknown(data['file_hash']!, _fileHashMeta),
      );
    } else if (isInserting) {
      context.missing(_fileHashMeta);
    }
    if (data.containsKey('ext')) {
      context.handle(
        _extMeta,
        ext.isAcceptableOrUnknown(data['ext']!, _extMeta),
      );
    } else if (isInserting) {
      context.missing(_extMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FontRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FontRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clock'],
      )!,
      originDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      family: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}family'],
      )!,
      fileHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_hash'],
      )!,
      ext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ext'],
      )!,
    );
  }

  @override
  $FontsTable createAlias(String alias) {
    return $FontsTable(attachedDatabase, alias);
  }
}

class FontRow extends DataClass implements Insertable<FontRow> {
  final String id;
  final String clock;
  final String originDevice;
  final bool deleted;
  final int localSeq;
  final String family;
  final String fileHash;

  /// 'ttf' | 'otf'
  final String ext;
  const FontRow({
    required this.id,
    required this.clock,
    required this.originDevice,
    required this.deleted,
    required this.localSeq,
    required this.family,
    required this.fileHash,
    required this.ext,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['clock'] = Variable<String>(clock);
    map['origin_device'] = Variable<String>(originDevice);
    map['deleted'] = Variable<bool>(deleted);
    map['local_seq'] = Variable<int>(localSeq);
    map['family'] = Variable<String>(family);
    map['file_hash'] = Variable<String>(fileHash);
    map['ext'] = Variable<String>(ext);
    return map;
  }

  FontsCompanion toCompanion(bool nullToAbsent) {
    return FontsCompanion(
      id: Value(id),
      clock: Value(clock),
      originDevice: Value(originDevice),
      deleted: Value(deleted),
      localSeq: Value(localSeq),
      family: Value(family),
      fileHash: Value(fileHash),
      ext: Value(ext),
    );
  }

  factory FontRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FontRow(
      id: serializer.fromJson<String>(json['id']),
      clock: serializer.fromJson<String>(json['clock']),
      originDevice: serializer.fromJson<String>(json['originDevice']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      localSeq: serializer.fromJson<int>(json['localSeq']),
      family: serializer.fromJson<String>(json['family']),
      fileHash: serializer.fromJson<String>(json['fileHash']),
      ext: serializer.fromJson<String>(json['ext']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clock': serializer.toJson<String>(clock),
      'originDevice': serializer.toJson<String>(originDevice),
      'deleted': serializer.toJson<bool>(deleted),
      'localSeq': serializer.toJson<int>(localSeq),
      'family': serializer.toJson<String>(family),
      'fileHash': serializer.toJson<String>(fileHash),
      'ext': serializer.toJson<String>(ext),
    };
  }

  FontRow copyWith({
    String? id,
    String? clock,
    String? originDevice,
    bool? deleted,
    int? localSeq,
    String? family,
    String? fileHash,
    String? ext,
  }) => FontRow(
    id: id ?? this.id,
    clock: clock ?? this.clock,
    originDevice: originDevice ?? this.originDevice,
    deleted: deleted ?? this.deleted,
    localSeq: localSeq ?? this.localSeq,
    family: family ?? this.family,
    fileHash: fileHash ?? this.fileHash,
    ext: ext ?? this.ext,
  );
  FontRow copyWithCompanion(FontsCompanion data) {
    return FontRow(
      id: data.id.present ? data.id.value : this.id,
      clock: data.clock.present ? data.clock.value : this.clock,
      originDevice: data.originDevice.present
          ? data.originDevice.value
          : this.originDevice,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      family: data.family.present ? data.family.value : this.family,
      fileHash: data.fileHash.present ? data.fileHash.value : this.fileHash,
      ext: data.ext.present ? data.ext.value : this.ext,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FontRow(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('family: $family, ')
          ..write('fileHash: $fileHash, ')
          ..write('ext: $ext')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    family,
    fileHash,
    ext,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FontRow &&
          other.id == this.id &&
          other.clock == this.clock &&
          other.originDevice == this.originDevice &&
          other.deleted == this.deleted &&
          other.localSeq == this.localSeq &&
          other.family == this.family &&
          other.fileHash == this.fileHash &&
          other.ext == this.ext);
}

class FontsCompanion extends UpdateCompanion<FontRow> {
  final Value<String> id;
  final Value<String> clock;
  final Value<String> originDevice;
  final Value<bool> deleted;
  final Value<int> localSeq;
  final Value<String> family;
  final Value<String> fileHash;
  final Value<String> ext;
  final Value<int> rowid;
  const FontsCompanion({
    this.id = const Value.absent(),
    this.clock = const Value.absent(),
    this.originDevice = const Value.absent(),
    this.deleted = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.family = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.ext = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FontsCompanion.insert({
    required String id,
    required String clock,
    required String originDevice,
    this.deleted = const Value.absent(),
    required int localSeq,
    required String family,
    required String fileHash,
    required String ext,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clock = Value(clock),
       originDevice = Value(originDevice),
       localSeq = Value(localSeq),
       family = Value(family),
       fileHash = Value(fileHash),
       ext = Value(ext);
  static Insertable<FontRow> custom({
    Expression<String>? id,
    Expression<String>? clock,
    Expression<String>? originDevice,
    Expression<bool>? deleted,
    Expression<int>? localSeq,
    Expression<String>? family,
    Expression<String>? fileHash,
    Expression<String>? ext,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clock != null) 'clock': clock,
      if (originDevice != null) 'origin_device': originDevice,
      if (deleted != null) 'deleted': deleted,
      if (localSeq != null) 'local_seq': localSeq,
      if (family != null) 'family': family,
      if (fileHash != null) 'file_hash': fileHash,
      if (ext != null) 'ext': ext,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FontsCompanion copyWith({
    Value<String>? id,
    Value<String>? clock,
    Value<String>? originDevice,
    Value<bool>? deleted,
    Value<int>? localSeq,
    Value<String>? family,
    Value<String>? fileHash,
    Value<String>? ext,
    Value<int>? rowid,
  }) {
    return FontsCompanion(
      id: id ?? this.id,
      clock: clock ?? this.clock,
      originDevice: originDevice ?? this.originDevice,
      deleted: deleted ?? this.deleted,
      localSeq: localSeq ?? this.localSeq,
      family: family ?? this.family,
      fileHash: fileHash ?? this.fileHash,
      ext: ext ?? this.ext,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clock.present) {
      map['clock'] = Variable<String>(clock.value);
    }
    if (originDevice.present) {
      map['origin_device'] = Variable<String>(originDevice.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (family.present) {
      map['family'] = Variable<String>(family.value);
    }
    if (fileHash.present) {
      map['file_hash'] = Variable<String>(fileHash.value);
    }
    if (ext.present) {
      map['ext'] = Variable<String>(ext.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FontsCompanion(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('family: $family, ')
          ..write('fileHash: $fileHash, ')
          ..write('ext: $ext, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LyricsTable extends Lyrics with TableInfo<$LyricsTable, LyricsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LyricsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clockMeta = const VerificationMeta('clock');
  @override
  late final GeneratedColumn<String> clock = GeneratedColumn<String>(
    'clock',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originDeviceMeta = const VerificationMeta(
    'originDevice',
  );
  @override
  late final GeneratedColumn<String> originDevice = GeneratedColumn<String>(
    'origin_device',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    kind,
    body,
    source,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lyrics';
  @override
  VerificationContext validateIntegrity(
    Insertable<LyricsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('clock')) {
      context.handle(
        _clockMeta,
        clock.isAcceptableOrUnknown(data['clock']!, _clockMeta),
      );
    } else if (isInserting) {
      context.missing(_clockMeta);
    }
    if (data.containsKey('origin_device')) {
      context.handle(
        _originDeviceMeta,
        originDevice.isAcceptableOrUnknown(
          data['origin_device']!,
          _originDeviceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_localSeqMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LyricsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LyricsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clock: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clock'],
      )!,
      originDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $LyricsTable createAlias(String alias) {
    return $LyricsTable(attachedDatabase, alias);
  }
}

class LyricsRow extends DataClass implements Insertable<LyricsRow> {
  final String id;
  final String clock;
  final String originDevice;
  final bool deleted;
  final int localSeq;

  /// 'synced' | 'plain' | 'none'
  final String kind;

  /// LRC text for synced, plain text for plain, empty for none.
  final String body;

  /// 'lrclib' | 'youtube'; null for none.
  final String? source;
  final DateTime fetchedAt;
  const LyricsRow({
    required this.id,
    required this.clock,
    required this.originDevice,
    required this.deleted,
    required this.localSeq,
    required this.kind,
    required this.body,
    this.source,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['clock'] = Variable<String>(clock);
    map['origin_device'] = Variable<String>(originDevice);
    map['deleted'] = Variable<bool>(deleted);
    map['local_seq'] = Variable<int>(localSeq);
    map['kind'] = Variable<String>(kind);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  LyricsCompanion toCompanion(bool nullToAbsent) {
    return LyricsCompanion(
      id: Value(id),
      clock: Value(clock),
      originDevice: Value(originDevice),
      deleted: Value(deleted),
      localSeq: Value(localSeq),
      kind: Value(kind),
      body: Value(body),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory LyricsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LyricsRow(
      id: serializer.fromJson<String>(json['id']),
      clock: serializer.fromJson<String>(json['clock']),
      originDevice: serializer.fromJson<String>(json['originDevice']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      localSeq: serializer.fromJson<int>(json['localSeq']),
      kind: serializer.fromJson<String>(json['kind']),
      body: serializer.fromJson<String>(json['body']),
      source: serializer.fromJson<String?>(json['source']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clock': serializer.toJson<String>(clock),
      'originDevice': serializer.toJson<String>(originDevice),
      'deleted': serializer.toJson<bool>(deleted),
      'localSeq': serializer.toJson<int>(localSeq),
      'kind': serializer.toJson<String>(kind),
      'body': serializer.toJson<String>(body),
      'source': serializer.toJson<String?>(source),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  LyricsRow copyWith({
    String? id,
    String? clock,
    String? originDevice,
    bool? deleted,
    int? localSeq,
    String? kind,
    String? body,
    Value<String?> source = const Value.absent(),
    DateTime? fetchedAt,
  }) => LyricsRow(
    id: id ?? this.id,
    clock: clock ?? this.clock,
    originDevice: originDevice ?? this.originDevice,
    deleted: deleted ?? this.deleted,
    localSeq: localSeq ?? this.localSeq,
    kind: kind ?? this.kind,
    body: body ?? this.body,
    source: source.present ? source.value : this.source,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  LyricsRow copyWithCompanion(LyricsCompanion data) {
    return LyricsRow(
      id: data.id.present ? data.id.value : this.id,
      clock: data.clock.present ? data.clock.value : this.clock,
      originDevice: data.originDevice.present
          ? data.originDevice.value
          : this.originDevice,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      kind: data.kind.present ? data.kind.value : this.kind,
      body: data.body.present ? data.body.value : this.body,
      source: data.source.present ? data.source.value : this.source,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LyricsRow(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('source: $source, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clock,
    originDevice,
    deleted,
    localSeq,
    kind,
    body,
    source,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LyricsRow &&
          other.id == this.id &&
          other.clock == this.clock &&
          other.originDevice == this.originDevice &&
          other.deleted == this.deleted &&
          other.localSeq == this.localSeq &&
          other.kind == this.kind &&
          other.body == this.body &&
          other.source == this.source &&
          other.fetchedAt == this.fetchedAt);
}

class LyricsCompanion extends UpdateCompanion<LyricsRow> {
  final Value<String> id;
  final Value<String> clock;
  final Value<String> originDevice;
  final Value<bool> deleted;
  final Value<int> localSeq;
  final Value<String> kind;
  final Value<String> body;
  final Value<String?> source;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const LyricsCompanion({
    this.id = const Value.absent(),
    this.clock = const Value.absent(),
    this.originDevice = const Value.absent(),
    this.deleted = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.kind = const Value.absent(),
    this.body = const Value.absent(),
    this.source = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LyricsCompanion.insert({
    required String id,
    required String clock,
    required String originDevice,
    this.deleted = const Value.absent(),
    required int localSeq,
    required String kind,
    required String body,
    this.source = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clock = Value(clock),
       originDevice = Value(originDevice),
       localSeq = Value(localSeq),
       kind = Value(kind),
       body = Value(body),
       fetchedAt = Value(fetchedAt);
  static Insertable<LyricsRow> custom({
    Expression<String>? id,
    Expression<String>? clock,
    Expression<String>? originDevice,
    Expression<bool>? deleted,
    Expression<int>? localSeq,
    Expression<String>? kind,
    Expression<String>? body,
    Expression<String>? source,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clock != null) 'clock': clock,
      if (originDevice != null) 'origin_device': originDevice,
      if (deleted != null) 'deleted': deleted,
      if (localSeq != null) 'local_seq': localSeq,
      if (kind != null) 'kind': kind,
      if (body != null) 'body': body,
      if (source != null) 'source': source,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LyricsCompanion copyWith({
    Value<String>? id,
    Value<String>? clock,
    Value<String>? originDevice,
    Value<bool>? deleted,
    Value<int>? localSeq,
    Value<String>? kind,
    Value<String>? body,
    Value<String?>? source,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return LyricsCompanion(
      id: id ?? this.id,
      clock: clock ?? this.clock,
      originDevice: originDevice ?? this.originDevice,
      deleted: deleted ?? this.deleted,
      localSeq: localSeq ?? this.localSeq,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      source: source ?? this.source,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clock.present) {
      map['clock'] = Variable<String>(clock.value);
    }
    if (originDevice.present) {
      map['origin_device'] = Variable<String>(originDevice.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCompanion(')
          ..write('id: $id, ')
          ..write('clock: $clock, ')
          ..write('originDevice: $originDevice, ')
          ..write('deleted: $deleted, ')
          ..write('localSeq: $localSeq, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('source: $source, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $PlaylistEntriesTable playlistEntries = $PlaylistEntriesTable(
    this,
  );
  late final $YtSeenTable ytSeen = $YtSeenTable(this);
  late final $LocalFilesTable localFiles = $LocalFilesTable(this);
  late final $PlaylistDevicePrefsTable playlistDevicePrefs =
      $PlaylistDevicePrefsTable(this);
  late final $LibraryFoldersTable libraryFolders = $LibraryFoldersTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $PlayHistoryTable playHistory = $PlayHistoryTable(this);
  late final $ThemesTable themes = $ThemesTable(this);
  late final $FontsTable fonts = $FontsTable(this);
  late final $LyricsTable lyrics = $LyricsTable(this);
  late final Index playlistEntriesPlaylistPosition = Index(
    'playlist_entries_playlist_position',
    'CREATE INDEX playlist_entries_playlist_position ON playlist_entries (playlist_id, position)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    playlists,
    playlistEntries,
    ytSeen,
    localFiles,
    playlistDevicePrefs,
    libraryFolders,
    settings,
    playHistory,
    themes,
    fonts,
    lyrics,
    playlistEntriesPlaylistPosition,
  ];
}

typedef $$TracksTableCreateCompanionBuilder = TracksCompanion Function({
  required String id,
  required String clock,
  required String originDevice,
  Value<bool> deleted,
  required int localSeq,
  required String source,
  Value<String?> ytVideoId,
  required String title,
  required String artist,
  Value<String?> album,
  Value<int> durationMs,
  Value<String?> artworkRef,
  Value<String?> fileHash,
  Value<bool> unavailable,
  required String searchText,
  Value<int> rowid,
});
typedef $$TracksTableUpdateCompanionBuilder = TracksCompanion Function({
  Value<String> id,
  Value<String> clock,
  Value<String> originDevice,
  Value<bool> deleted,
  Value<int> localSeq,
  Value<String> source,
  Value<String?> ytVideoId,
  Value<String> title,
  Value<String> artist,
  Value<String?> album,
  Value<int> durationMs,
  Value<String?> artworkRef,
  Value<String?> fileHash,
  Value<bool> unavailable,
  Value<String> searchText,
  Value<int> rowid,
});

class $$TracksTableFilterComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ytVideoId => $composableBuilder(
    column: $table.ytVideoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkRef => $composableBuilder(
    column: $table.artworkRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get unavailable => $composableBuilder(
    column: $table.unavailable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TracksTableOrderingComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ytVideoId => $composableBuilder(
    column: $table.ytVideoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkRef => $composableBuilder(
    column: $table.artworkRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get unavailable => $composableBuilder(
    column: $table.unavailable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clock =>
      $composableBuilder(column: $table.clock, builder: (column) => column);

  GeneratedColumn<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get ytVideoId =>
      $composableBuilder(column: $table.ytVideoId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artworkRef => $composableBuilder(
    column: $table.artworkRef,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileHash =>
      $composableBuilder(column: $table.fileHash, builder: (column) => column);

  GeneratedColumn<bool> get unavailable => $composableBuilder(
    column: $table.unavailable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TracksTable,
          Track,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (Track, BaseReferences<_$AppDatabase, $TracksTable, Track>),
          Track,
          PrefetchHooks Function()
        > {
  $$TracksTableTableManager(_$AppDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clock = const Value.absent(),
                Value<String> originDevice = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> ytVideoId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> artworkRef = const Value.absent(),
                Value<String?> fileHash = const Value.absent(),
                Value<bool> unavailable = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                source: source,
                ytVideoId: ytVideoId,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                artworkRef: artworkRef,
                fileHash: fileHash,
                unavailable: unavailable,
                searchText: searchText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clock,
                required String originDevice,
                Value<bool> deleted = const Value.absent(),
                required int localSeq,
                required String source,
                Value<String?> ytVideoId = const Value.absent(),
                required String title,
                required String artist,
                Value<String?> album = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> artworkRef = const Value.absent(),
                Value<String?> fileHash = const Value.absent(),
                Value<bool> unavailable = const Value.absent(),
                required String searchText,
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion.insert(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                source: source,
                ytVideoId: ytVideoId,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs,
                artworkRef: artworkRef,
                fileHash: fileHash,
                unavailable: unavailable,
                searchText: searchText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TracksTable, Track>(table),
                  BaseReferences<_$AppDatabase, $TracksTable, Track>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TracksTable,
      Track,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (Track, BaseReferences<_$AppDatabase, $TracksTable, Track>),
      Track,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder = PlaylistsCompanion Function({
  required String id,
  required String clock,
  required String originDevice,
  Value<bool> deleted,
  required int localSeq,
  required String name,
  Value<String?> coverRef,
  required String source,
  Value<String?> ytPlaylistUrl,
  Value<DateTime?> lastYtSyncAt,
  Value<int> rowid,
});
typedef $$PlaylistsTableUpdateCompanionBuilder = PlaylistsCompanion Function({
  Value<String> id,
  Value<String> clock,
  Value<String> originDevice,
  Value<bool> deleted,
  Value<int> localSeq,
  Value<String> name,
  Value<String?> coverRef,
  Value<String> source,
  Value<String?> ytPlaylistUrl,
  Value<DateTime?> lastYtSyncAt,
  Value<int> rowid,
});

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverRef => $composableBuilder(
    column: $table.coverRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ytPlaylistUrl => $composableBuilder(
    column: $table.ytPlaylistUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastYtSyncAt => $composableBuilder(
    column: $table.lastYtSyncAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverRef => $composableBuilder(
    column: $table.coverRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ytPlaylistUrl => $composableBuilder(
    column: $table.ytPlaylistUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastYtSyncAt => $composableBuilder(
    column: $table.lastYtSyncAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clock =>
      $composableBuilder(column: $table.clock, builder: (column) => column);

  GeneratedColumn<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get coverRef =>
      $composableBuilder(column: $table.coverRef, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get ytPlaylistUrl => $composableBuilder(
    column: $table.ytPlaylistUrl,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastYtSyncAt => $composableBuilder(
    column: $table.lastYtSyncAt,
    builder: (column) => column,
  );
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          Playlist,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (Playlist, BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>),
          Playlist,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clock = const Value.absent(),
                Value<String> originDevice = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> coverRef = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> ytPlaylistUrl = const Value.absent(),
                Value<DateTime?> lastYtSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                name: name,
                coverRef: coverRef,
                source: source,
                ytPlaylistUrl: ytPlaylistUrl,
                lastYtSyncAt: lastYtSyncAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clock,
                required String originDevice,
                Value<bool> deleted = const Value.absent(),
                required int localSeq,
                required String name,
                Value<String?> coverRef = const Value.absent(),
                required String source,
                Value<String?> ytPlaylistUrl = const Value.absent(),
                Value<DateTime?> lastYtSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                name: name,
                coverRef: coverRef,
                source: source,
                ytPlaylistUrl: ytPlaylistUrl,
                lastYtSyncAt: lastYtSyncAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistsTable, Playlist>(table),
                  BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      Playlist,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (Playlist, BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>),
      Playlist,
      PrefetchHooks Function()
    >;
typedef $$PlaylistEntriesTableCreateCompanionBuilder =
    PlaylistEntriesCompanion Function({
      required String id,
      required String clock,
      required String originDevice,
      Value<bool> deleted,
      required int localSeq,
      required String playlistId,
      required String trackId,
      required String position,
      Value<String> status,
      Value<bool> kept,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$PlaylistEntriesTableUpdateCompanionBuilder =
    PlaylistEntriesCompanion Function({
      Value<String> id,
      Value<String> clock,
      Value<String> originDevice,
      Value<bool> deleted,
      Value<int> localSeq,
      Value<String> playlistId,
      Value<String> trackId,
      Value<String> position,
      Value<String> status,
      Value<bool> kept,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$PlaylistEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTable> {
  $$PlaylistEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get kept => $composableBuilder(
    column: $table.kept,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTable> {
  $$PlaylistEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get kept => $composableBuilder(
    column: $table.kept,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTable> {
  $$PlaylistEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clock =>
      $composableBuilder(column: $table.clock, builder: (column) => column);

  GeneratedColumn<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get kept =>
      $composableBuilder(column: $table.kept, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$PlaylistEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistEntriesTable,
          PlaylistEntry,
          $$PlaylistEntriesTableFilterComposer,
          $$PlaylistEntriesTableOrderingComposer,
          $$PlaylistEntriesTableAnnotationComposer,
          $$PlaylistEntriesTableCreateCompanionBuilder,
          $$PlaylistEntriesTableUpdateCompanionBuilder,
          (
            PlaylistEntry,
            BaseReferences<_$AppDatabase, $PlaylistEntriesTable, PlaylistEntry>,
          ),
          PlaylistEntry,
          PrefetchHooks Function()
        > {
  $$PlaylistEntriesTableTableManager(
    _$AppDatabase db,
    $PlaylistEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clock = const Value.absent(),
                Value<String> originDevice = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<String> position = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> kept = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistEntriesCompanion(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                playlistId: playlistId,
                trackId: trackId,
                position: position,
                status: status,
                kept: kept,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clock,
                required String originDevice,
                Value<bool> deleted = const Value.absent(),
                required int localSeq,
                required String playlistId,
                required String trackId,
                required String position,
                Value<String> status = const Value.absent(),
                Value<bool> kept = const Value.absent(),
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistEntriesCompanion.insert(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                playlistId: playlistId,
                trackId: trackId,
                position: position,
                status: status,
                kept: kept,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistEntriesTable, PlaylistEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PlaylistEntriesTable,
                    PlaylistEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistEntriesTable,
      PlaylistEntry,
      $$PlaylistEntriesTableFilterComposer,
      $$PlaylistEntriesTableOrderingComposer,
      $$PlaylistEntriesTableAnnotationComposer,
      $$PlaylistEntriesTableCreateCompanionBuilder,
      $$PlaylistEntriesTableUpdateCompanionBuilder,
      (
        PlaylistEntry,
        BaseReferences<_$AppDatabase, $PlaylistEntriesTable, PlaylistEntry>,
      ),
      PlaylistEntry,
      PrefetchHooks Function()
    >;
typedef $$YtSeenTableCreateCompanionBuilder = YtSeenCompanion Function({
  required String id,
  required String clock,
  required String originDevice,
  Value<bool> deleted,
  required int localSeq,
  required String playlistId,
  required String videoId,
  Value<int> rowid,
});
typedef $$YtSeenTableUpdateCompanionBuilder = YtSeenCompanion Function({
  Value<String> id,
  Value<String> clock,
  Value<String> originDevice,
  Value<bool> deleted,
  Value<int> localSeq,
  Value<String> playlistId,
  Value<String> videoId,
  Value<int> rowid,
});

class $$YtSeenTableFilterComposer
    extends Composer<_$AppDatabase, $YtSeenTable> {
  $$YtSeenTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$YtSeenTableOrderingComposer
    extends Composer<_$AppDatabase, $YtSeenTable> {
  $$YtSeenTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get videoId => $composableBuilder(
    column: $table.videoId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$YtSeenTableAnnotationComposer
    extends Composer<_$AppDatabase, $YtSeenTable> {
  $$YtSeenTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clock =>
      $composableBuilder(column: $table.clock, builder: (column) => column);

  GeneratedColumn<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get videoId =>
      $composableBuilder(column: $table.videoId, builder: (column) => column);
}

class $$YtSeenTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $YtSeenTable,
          YtSeenData,
          $$YtSeenTableFilterComposer,
          $$YtSeenTableOrderingComposer,
          $$YtSeenTableAnnotationComposer,
          $$YtSeenTableCreateCompanionBuilder,
          $$YtSeenTableUpdateCompanionBuilder,
          (YtSeenData, BaseReferences<_$AppDatabase, $YtSeenTable, YtSeenData>),
          YtSeenData,
          PrefetchHooks Function()
        > {
  $$YtSeenTableTableManager(_$AppDatabase db, $YtSeenTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$YtSeenTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$YtSeenTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$YtSeenTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clock = const Value.absent(),
                Value<String> originDevice = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<String> videoId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YtSeenCompanion(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                playlistId: playlistId,
                videoId: videoId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clock,
                required String originDevice,
                Value<bool> deleted = const Value.absent(),
                required int localSeq,
                required String playlistId,
                required String videoId,
                Value<int> rowid = const Value.absent(),
              }) => YtSeenCompanion.insert(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                playlistId: playlistId,
                videoId: videoId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$YtSeenTable, YtSeenData>(table),
                  BaseReferences<_$AppDatabase, $YtSeenTable, YtSeenData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$YtSeenTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $YtSeenTable,
      YtSeenData,
      $$YtSeenTableFilterComposer,
      $$YtSeenTableOrderingComposer,
      $$YtSeenTableAnnotationComposer,
      $$YtSeenTableCreateCompanionBuilder,
      $$YtSeenTableUpdateCompanionBuilder,
      (YtSeenData, BaseReferences<_$AppDatabase, $YtSeenTable, YtSeenData>),
      YtSeenData,
      PrefetchHooks Function()
    >;
typedef $$LocalFilesTableCreateCompanionBuilder = LocalFilesCompanion Function({
  required String trackId,
  required String path,
  required String state,
  required int bytes,
  required int mtimeMs,
  Value<String?> error,
  Value<int?> requestedAt,
  Value<bool> manual,
  Value<int> rowid,
});
typedef $$LocalFilesTableUpdateCompanionBuilder = LocalFilesCompanion Function({
  Value<String> trackId,
  Value<String> path,
  Value<String> state,
  Value<int> bytes,
  Value<int> mtimeMs,
  Value<String?> error,
  Value<int?> requestedAt,
  Value<bool> manual,
  Value<int> rowid,
});

class $$LocalFilesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalFilesTable> {
  $$LocalFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mtimeMs => $composableBuilder(
    column: $table.mtimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get manual => $composableBuilder(
    column: $table.manual,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalFilesTable> {
  $$LocalFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mtimeMs => $composableBuilder(
    column: $table.mtimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get manual => $composableBuilder(
    column: $table.manual,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalFilesTable> {
  $$LocalFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<int> get mtimeMs =>
      $composableBuilder(column: $table.mtimeMs, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get manual =>
      $composableBuilder(column: $table.manual, builder: (column) => column);
}

class $$LocalFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalFilesTable,
          LocalFile,
          $$LocalFilesTableFilterComposer,
          $$LocalFilesTableOrderingComposer,
          $$LocalFilesTableAnnotationComposer,
          $$LocalFilesTableCreateCompanionBuilder,
          $$LocalFilesTableUpdateCompanionBuilder,
          (
            LocalFile,
            BaseReferences<_$AppDatabase, $LocalFilesTable, LocalFile>,
          ),
          LocalFile,
          PrefetchHooks Function()
        > {
  $$LocalFilesTableTableManager(_$AppDatabase db, $LocalFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> trackId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> bytes = const Value.absent(),
                Value<int> mtimeMs = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int?> requestedAt = const Value.absent(),
                Value<bool> manual = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFilesCompanion(
                trackId: trackId,
                path: path,
                state: state,
                bytes: bytes,
                mtimeMs: mtimeMs,
                error: error,
                requestedAt: requestedAt,
                manual: manual,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackId,
                required String path,
                required String state,
                required int bytes,
                required int mtimeMs,
                Value<String?> error = const Value.absent(),
                Value<int?> requestedAt = const Value.absent(),
                Value<bool> manual = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFilesCompanion.insert(
                trackId: trackId,
                path: path,
                state: state,
                bytes: bytes,
                mtimeMs: mtimeMs,
                error: error,
                requestedAt: requestedAt,
                manual: manual,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalFilesTable, LocalFile>(table),
                  BaseReferences<_$AppDatabase, $LocalFilesTable, LocalFile>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalFilesTable,
      LocalFile,
      $$LocalFilesTableFilterComposer,
      $$LocalFilesTableOrderingComposer,
      $$LocalFilesTableAnnotationComposer,
      $$LocalFilesTableCreateCompanionBuilder,
      $$LocalFilesTableUpdateCompanionBuilder,
      (LocalFile, BaseReferences<_$AppDatabase, $LocalFilesTable, LocalFile>),
      LocalFile,
      PrefetchHooks Function()
    >;
typedef $$PlaylistDevicePrefsTableCreateCompanionBuilder =
    PlaylistDevicePrefsCompanion Function({
      required String playlistId,
      Value<bool> downloadEnabled,
      Value<int> rowid,
    });
typedef $$PlaylistDevicePrefsTableUpdateCompanionBuilder =
    PlaylistDevicePrefsCompanion Function({
      Value<String> playlistId,
      Value<bool> downloadEnabled,
      Value<int> rowid,
    });

class $$PlaylistDevicePrefsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistDevicePrefsTable> {
  $$PlaylistDevicePrefsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get downloadEnabled => $composableBuilder(
    column: $table.downloadEnabled,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistDevicePrefsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistDevicePrefsTable> {
  $$PlaylistDevicePrefsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get downloadEnabled => $composableBuilder(
    column: $table.downloadEnabled,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistDevicePrefsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistDevicePrefsTable> {
  $$PlaylistDevicePrefsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get downloadEnabled => $composableBuilder(
    column: $table.downloadEnabled,
    builder: (column) => column,
  );
}

class $$PlaylistDevicePrefsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistDevicePrefsTable,
          PlaylistDevicePref,
          $$PlaylistDevicePrefsTableFilterComposer,
          $$PlaylistDevicePrefsTableOrderingComposer,
          $$PlaylistDevicePrefsTableAnnotationComposer,
          $$PlaylistDevicePrefsTableCreateCompanionBuilder,
          $$PlaylistDevicePrefsTableUpdateCompanionBuilder,
          (
            PlaylistDevicePref,
            BaseReferences<
              _$AppDatabase,
              $PlaylistDevicePrefsTable,
              PlaylistDevicePref
            >,
          ),
          PlaylistDevicePref,
          PrefetchHooks Function()
        > {
  $$PlaylistDevicePrefsTableTableManager(
    _$AppDatabase db,
    $PlaylistDevicePrefsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistDevicePrefsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistDevicePrefsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlaylistDevicePrefsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> playlistId = const Value.absent(),
                Value<bool> downloadEnabled = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistDevicePrefsCompanion(
                playlistId: playlistId,
                downloadEnabled: downloadEnabled,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistId,
                Value<bool> downloadEnabled = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistDevicePrefsCompanion.insert(
                playlistId: playlistId,
                downloadEnabled: downloadEnabled,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistDevicePrefsTable, PlaylistDevicePref>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $PlaylistDevicePrefsTable,
                    PlaylistDevicePref
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistDevicePrefsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistDevicePrefsTable,
      PlaylistDevicePref,
      $$PlaylistDevicePrefsTableFilterComposer,
      $$PlaylistDevicePrefsTableOrderingComposer,
      $$PlaylistDevicePrefsTableAnnotationComposer,
      $$PlaylistDevicePrefsTableCreateCompanionBuilder,
      $$PlaylistDevicePrefsTableUpdateCompanionBuilder,
      (
        PlaylistDevicePref,
        BaseReferences<
          _$AppDatabase,
          $PlaylistDevicePrefsTable,
          PlaylistDevicePref
        >,
      ),
      PlaylistDevicePref,
      PrefetchHooks Function()
    >;
typedef $$LibraryFoldersTableCreateCompanionBuilder =
    LibraryFoldersCompanion Function({
      required String path,
      Value<DateTime?> lastScanAt,
      Value<int> rowid,
    });
typedef $$LibraryFoldersTableUpdateCompanionBuilder =
    LibraryFoldersCompanion Function({
      Value<String> path,
      Value<DateTime?> lastScanAt,
      Value<int> rowid,
    });

class $$LibraryFoldersTableFilterComposer
    extends Composer<_$AppDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibraryFoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryFoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $LibraryFoldersTable> {
  $$LibraryFoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => column,
  );
}

class $$LibraryFoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LibraryFoldersTable,
          LibraryFolder,
          $$LibraryFoldersTableFilterComposer,
          $$LibraryFoldersTableOrderingComposer,
          $$LibraryFoldersTableAnnotationComposer,
          $$LibraryFoldersTableCreateCompanionBuilder,
          $$LibraryFoldersTableUpdateCompanionBuilder,
          (
            LibraryFolder,
            BaseReferences<_$AppDatabase, $LibraryFoldersTable, LibraryFolder>,
          ),
          LibraryFolder,
          PrefetchHooks Function()
        > {
  $$LibraryFoldersTableTableManager(
    _$AppDatabase db,
    $LibraryFoldersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryFoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryFoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryFoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<DateTime?> lastScanAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryFoldersCompanion(
                path: path,
                lastScanAt: lastScanAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                Value<DateTime?> lastScanAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryFoldersCompanion.insert(
                path: path,
                lastScanAt: lastScanAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LibraryFoldersTable, LibraryFolder>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LibraryFoldersTable,
                    LibraryFolder
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibraryFoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LibraryFoldersTable,
      LibraryFolder,
      $$LibraryFoldersTableFilterComposer,
      $$LibraryFoldersTableOrderingComposer,
      $$LibraryFoldersTableAnnotationComposer,
      $$LibraryFoldersTableCreateCompanionBuilder,
      $$LibraryFoldersTableUpdateCompanionBuilder,
      (
        LibraryFolder,
        BaseReferences<_$AppDatabase, $LibraryFoldersTable, LibraryFolder>,
      ),
      LibraryFolder,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$PlayHistoryTableCreateCompanionBuilder =
    PlayHistoryCompanion Function({
      Value<int> id,
      required String trackId,
      Value<String?> playlistId,
      required DateTime playedAt,
    });
typedef $$PlayHistoryTableUpdateCompanionBuilder =
    PlayHistoryCompanion Function({
      Value<int> id,
      Value<String> trackId,
      Value<String?> playlistId,
      Value<DateTime> playedAt,
    });

class $$PlayHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlayHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayHistoryTable> {
  $$PlayHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);
}

class $$PlayHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayHistoryTable,
          PlayHistoryEntry,
          $$PlayHistoryTableFilterComposer,
          $$PlayHistoryTableOrderingComposer,
          $$PlayHistoryTableAnnotationComposer,
          $$PlayHistoryTableCreateCompanionBuilder,
          $$PlayHistoryTableUpdateCompanionBuilder,
          (
            PlayHistoryEntry,
            BaseReferences<_$AppDatabase, $PlayHistoryTable, PlayHistoryEntry>,
          ),
          PlayHistoryEntry,
          PrefetchHooks Function()
        > {
  $$PlayHistoryTableTableManager(_$AppDatabase db, $PlayHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<String?> playlistId = const Value.absent(),
                Value<DateTime> playedAt = const Value.absent(),
              }) => PlayHistoryCompanion(
                id: id,
                trackId: trackId,
                playlistId: playlistId,
                playedAt: playedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String trackId,
                Value<String?> playlistId = const Value.absent(),
                required DateTime playedAt,
              }) => PlayHistoryCompanion.insert(
                id: id,
                trackId: trackId,
                playlistId: playlistId,
                playedAt: playedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlayHistoryTable, PlayHistoryEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PlayHistoryTable,
                    PlayHistoryEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayHistoryTable,
      PlayHistoryEntry,
      $$PlayHistoryTableFilterComposer,
      $$PlayHistoryTableOrderingComposer,
      $$PlayHistoryTableAnnotationComposer,
      $$PlayHistoryTableCreateCompanionBuilder,
      $$PlayHistoryTableUpdateCompanionBuilder,
      (
        PlayHistoryEntry,
        BaseReferences<_$AppDatabase, $PlayHistoryTable, PlayHistoryEntry>,
      ),
      PlayHistoryEntry,
      PrefetchHooks Function()
    >;
typedef $$ThemesTableCreateCompanionBuilder = ThemesCompanion Function({
  required String id,
  required String clock,
  required String originDevice,
  Value<bool> deleted,
  required int localSeq,
  required String name,
  required String specJson,
  Value<int> rowid,
});
typedef $$ThemesTableUpdateCompanionBuilder = ThemesCompanion Function({
  Value<String> id,
  Value<String> clock,
  Value<String> originDevice,
  Value<bool> deleted,
  Value<int> localSeq,
  Value<String> name,
  Value<String> specJson,
  Value<int> rowid,
});

class $$ThemesTableFilterComposer
    extends Composer<_$AppDatabase, $ThemesTable> {
  $$ThemesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get specJson => $composableBuilder(
    column: $table.specJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ThemesTableOrderingComposer
    extends Composer<_$AppDatabase, $ThemesTable> {
  $$ThemesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get specJson => $composableBuilder(
    column: $table.specJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ThemesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ThemesTable> {
  $$ThemesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clock =>
      $composableBuilder(column: $table.clock, builder: (column) => column);

  GeneratedColumn<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get specJson =>
      $composableBuilder(column: $table.specJson, builder: (column) => column);
}

class $$ThemesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ThemesTable,
          ThemeRow,
          $$ThemesTableFilterComposer,
          $$ThemesTableOrderingComposer,
          $$ThemesTableAnnotationComposer,
          $$ThemesTableCreateCompanionBuilder,
          $$ThemesTableUpdateCompanionBuilder,
          (ThemeRow, BaseReferences<_$AppDatabase, $ThemesTable, ThemeRow>),
          ThemeRow,
          PrefetchHooks Function()
        > {
  $$ThemesTableTableManager(_$AppDatabase db, $ThemesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThemesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThemesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThemesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clock = const Value.absent(),
                Value<String> originDevice = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> specJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThemesCompanion(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                name: name,
                specJson: specJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clock,
                required String originDevice,
                Value<bool> deleted = const Value.absent(),
                required int localSeq,
                required String name,
                required String specJson,
                Value<int> rowid = const Value.absent(),
              }) => ThemesCompanion.insert(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                name: name,
                specJson: specJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ThemesTable, ThemeRow>(table),
                  BaseReferences<_$AppDatabase, $ThemesTable, ThemeRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ThemesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ThemesTable,
      ThemeRow,
      $$ThemesTableFilterComposer,
      $$ThemesTableOrderingComposer,
      $$ThemesTableAnnotationComposer,
      $$ThemesTableCreateCompanionBuilder,
      $$ThemesTableUpdateCompanionBuilder,
      (ThemeRow, BaseReferences<_$AppDatabase, $ThemesTable, ThemeRow>),
      ThemeRow,
      PrefetchHooks Function()
    >;
typedef $$FontsTableCreateCompanionBuilder = FontsCompanion Function({
  required String id,
  required String clock,
  required String originDevice,
  Value<bool> deleted,
  required int localSeq,
  required String family,
  required String fileHash,
  required String ext,
  Value<int> rowid,
});
typedef $$FontsTableUpdateCompanionBuilder = FontsCompanion Function({
  Value<String> id,
  Value<String> clock,
  Value<String> originDevice,
  Value<bool> deleted,
  Value<int> localSeq,
  Value<String> family,
  Value<String> fileHash,
  Value<String> ext,
  Value<int> rowid,
});

class $$FontsTableFilterComposer extends Composer<_$AppDatabase, $FontsTable> {
  $$FontsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get family => $composableBuilder(
    column: $table.family,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ext => $composableBuilder(
    column: $table.ext,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FontsTableOrderingComposer
    extends Composer<_$AppDatabase, $FontsTable> {
  $$FontsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get family => $composableBuilder(
    column: $table.family,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ext => $composableBuilder(
    column: $table.ext,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FontsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FontsTable> {
  $$FontsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clock =>
      $composableBuilder(column: $table.clock, builder: (column) => column);

  GeneratedColumn<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get family =>
      $composableBuilder(column: $table.family, builder: (column) => column);

  GeneratedColumn<String> get fileHash =>
      $composableBuilder(column: $table.fileHash, builder: (column) => column);

  GeneratedColumn<String> get ext =>
      $composableBuilder(column: $table.ext, builder: (column) => column);
}

class $$FontsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FontsTable,
          FontRow,
          $$FontsTableFilterComposer,
          $$FontsTableOrderingComposer,
          $$FontsTableAnnotationComposer,
          $$FontsTableCreateCompanionBuilder,
          $$FontsTableUpdateCompanionBuilder,
          (FontRow, BaseReferences<_$AppDatabase, $FontsTable, FontRow>),
          FontRow,
          PrefetchHooks Function()
        > {
  $$FontsTableTableManager(_$AppDatabase db, $FontsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FontsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FontsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FontsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clock = const Value.absent(),
                Value<String> originDevice = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String> family = const Value.absent(),
                Value<String> fileHash = const Value.absent(),
                Value<String> ext = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FontsCompanion(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                family: family,
                fileHash: fileHash,
                ext: ext,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clock,
                required String originDevice,
                Value<bool> deleted = const Value.absent(),
                required int localSeq,
                required String family,
                required String fileHash,
                required String ext,
                Value<int> rowid = const Value.absent(),
              }) => FontsCompanion.insert(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                family: family,
                fileHash: fileHash,
                ext: ext,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FontsTable, FontRow>(table),
                  BaseReferences<_$AppDatabase, $FontsTable, FontRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FontsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FontsTable,
      FontRow,
      $$FontsTableFilterComposer,
      $$FontsTableOrderingComposer,
      $$FontsTableAnnotationComposer,
      $$FontsTableCreateCompanionBuilder,
      $$FontsTableUpdateCompanionBuilder,
      (FontRow, BaseReferences<_$AppDatabase, $FontsTable, FontRow>),
      FontRow,
      PrefetchHooks Function()
    >;
typedef $$LyricsTableCreateCompanionBuilder = LyricsCompanion Function({
  required String id,
  required String clock,
  required String originDevice,
  Value<bool> deleted,
  required int localSeq,
  required String kind,
  required String body,
  Value<String?> source,
  required DateTime fetchedAt,
  Value<int> rowid,
});
typedef $$LyricsTableUpdateCompanionBuilder = LyricsCompanion Function({
  Value<String> id,
  Value<String> clock,
  Value<String> originDevice,
  Value<bool> deleted,
  Value<int> localSeq,
  Value<String> kind,
  Value<String> body,
  Value<String?> source,
  Value<DateTime> fetchedAt,
  Value<int> rowid,
});

class $$LyricsTableFilterComposer
    extends Composer<_$AppDatabase, $LyricsTable> {
  $$LyricsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LyricsTableOrderingComposer
    extends Composer<_$AppDatabase, $LyricsTable> {
  $$LyricsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clock => $composableBuilder(
    column: $table.clock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LyricsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LyricsTable> {
  $$LyricsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clock =>
      $composableBuilder(column: $table.clock, builder: (column) => column);

  GeneratedColumn<String> get originDevice => $composableBuilder(
    column: $table.originDevice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$LyricsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LyricsTable,
          LyricsRow,
          $$LyricsTableFilterComposer,
          $$LyricsTableOrderingComposer,
          $$LyricsTableAnnotationComposer,
          $$LyricsTableCreateCompanionBuilder,
          $$LyricsTableUpdateCompanionBuilder,
          (LyricsRow, BaseReferences<_$AppDatabase, $LyricsTable, LyricsRow>),
          LyricsRow,
          PrefetchHooks Function()
        > {
  $$LyricsTableTableManager(_$AppDatabase db, $LyricsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LyricsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LyricsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LyricsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clock = const Value.absent(),
                Value<String> originDevice = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LyricsCompanion(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                kind: kind,
                body: body,
                source: source,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clock,
                required String originDevice,
                Value<bool> deleted = const Value.absent(),
                required int localSeq,
                required String kind,
                required String body,
                Value<String?> source = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => LyricsCompanion.insert(
                id: id,
                clock: clock,
                originDevice: originDevice,
                deleted: deleted,
                localSeq: localSeq,
                kind: kind,
                body: body,
                source: source,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LyricsTable, LyricsRow>(table),
                  BaseReferences<_$AppDatabase, $LyricsTable, LyricsRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LyricsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LyricsTable,
      LyricsRow,
      $$LyricsTableFilterComposer,
      $$LyricsTableOrderingComposer,
      $$LyricsTableAnnotationComposer,
      $$LyricsTableCreateCompanionBuilder,
      $$LyricsTableUpdateCompanionBuilder,
      (LyricsRow, BaseReferences<_$AppDatabase, $LyricsTable, LyricsRow>),
      LyricsRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$PlaylistEntriesTableTableManager get playlistEntries =>
      $$PlaylistEntriesTableTableManager(_db, _db.playlistEntries);
  $$YtSeenTableTableManager get ytSeen =>
      $$YtSeenTableTableManager(_db, _db.ytSeen);
  $$LocalFilesTableTableManager get localFiles =>
      $$LocalFilesTableTableManager(_db, _db.localFiles);
  $$PlaylistDevicePrefsTableTableManager get playlistDevicePrefs =>
      $$PlaylistDevicePrefsTableTableManager(_db, _db.playlistDevicePrefs);
  $$LibraryFoldersTableTableManager get libraryFolders =>
      $$LibraryFoldersTableTableManager(_db, _db.libraryFolders);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$PlayHistoryTableTableManager get playHistory =>
      $$PlayHistoryTableTableManager(_db, _db.playHistory);
  $$ThemesTableTableManager get themes =>
      $$ThemesTableTableManager(_db, _db.themes);
  $$FontsTableTableManager get fonts =>
      $$FontsTableTableManager(_db, _db.fonts);
  $$LyricsTableTableManager get lyrics =>
      $$LyricsTableTableManager(_db, _db.lyrics);
}
