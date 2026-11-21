/// Shapes returned by the DumpBox /v1 API.
library;

enum ItemType {
  note,
  link,
  file,
  image,
  location,
  voice;

  static ItemType parse(String v) => ItemType.values.firstWhere((t) => t.name == v, orElse: () => ItemType.note);

  String get label => switch (this) {
        ItemType.note => 'Notes',
        ItemType.link => 'Links',
        ItemType.image => 'Images',
        ItemType.file => 'Documents',
        ItemType.location => 'Places',
        ItemType.voice => 'Voice',
      };
}

class TagRef {
  TagRef({required this.id, required this.name, this.color});
  final String id;
  final String name;
  final String? color;

  factory TagRef.fromJson(Map<String, dynamic> j) => TagRef(id: j['id'] as String, name: j['name'] as String, color: j['color'] as String?);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
}

class FileMeta {
  FileMeta({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.localPath,
  });
  final String id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;

  /// Set only on this device while the file waits to upload.
  final String? localPath;

  bool get isImage => mimeType.startsWith('image/');
  bool get isAudio => mimeType.startsWith('audio/');

  factory FileMeta.fromJson(Map<String, dynamic> j) => FileMeta(
        id: j['id'] as String,
        fileName: j['file_name'] as String,
        mimeType: j['mime_type'] as String,
        sizeBytes: (j['size_bytes'] as num).toInt(),
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        localPath: j['local_path'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'file_name': fileName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'width': width,
        'height': height,
        if (localPath != null) 'local_path': localPath,
      };
}

class LinkMeta {
  LinkMeta({this.title, this.description, this.imageUrl, this.site});
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? site;
  factory LinkMeta.fromJson(Map<String, dynamic> j) => LinkMeta(
        title: j['title'] as String?,
        description: j['description'] as String?,
        imageUrl: j['image_url'] as String?,
        site: j['site'] as String?,
      );
  Map<String, dynamic> toJson() => {'title': title, 'description': description, 'image_url': imageUrl, 'site': site};
}

class Place {
  Place({required this.latitude, required this.longitude, this.label});
  final double latitude;
  final double longitude;
  final String? label;
  factory Place.fromJson(Map<String, dynamic> j) =>
      Place(latitude: (j['latitude'] as num).toDouble(), longitude: (j['longitude'] as num).toDouble(), label: j['label'] as String?);
  Map<String, dynamic> toJson() => {'latitude': latitude, 'longitude': longitude, 'label': label};
}

class Item {
  Item({
    required this.id,
    required this.type,
    this.title,
    this.body,
    this.url,
    this.link,
    this.location,
    this.pinned = false,
    this.starred = false,
    this.archivedAt,
    this.deletedAt,
    this.version = 0,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.collectionIds = const [],
    this.files = const [],
    this.source = 'android',
  });

  final String id;
  final ItemType type;
  final String? title;
  final String? body;
  final String? url;
  final LinkMeta? link;
  final Place? location;
  final bool pinned;
  final bool starred;
  final DateTime? archivedAt;
  final DateTime? deletedAt;

  /// 0 means "created on this device, not confirmed by the server yet".
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TagRef> tags;
  final List<String> collectionIds;
  final List<FileMeta> files;
  final String source;

  bool get isLocalOnly => version == 0;
  bool get isTrashed => deletedAt != null;
  bool get isArchived => archivedAt != null;

  /// All text that local (offline) search looks at.
  String get searchText => [
        title,
        body,
        url,
        link?.title,
        link?.description,
        location?.label,
        ...tags.map((t) => t.name),
        ...files.map((f) => f.fileName),
      ].whereType<String>().join(' ').toLowerCase();

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        type: ItemType.parse(j['type'] as String),
        title: j['title'] as String?,
        body: j['body'] as String?,
        url: j['url'] as String?,
        link: j['link'] == null ? null : LinkMeta.fromJson(j['link'] as Map<String, dynamic>),
        location: j['location'] == null ? null : Place.fromJson(j['location'] as Map<String, dynamic>),
        pinned: j['pinned'] as bool? ?? false,
        starred: j['starred'] as bool? ?? false,
        archivedAt: _date(j['archived_at']),
        deletedAt: _date(j['deleted_at']),
        version: (j['version'] as num?)?.toInt() ?? 0,
        createdAt: _date(j['created_at']) ?? DateTime.now().toUtc(),
        updatedAt: _date(j['updated_at']) ?? DateTime.now().toUtc(),
        tags: ((j['tags'] as List?) ?? const []).map((t) => TagRef.fromJson(t as Map<String, dynamic>)).toList(),
        collectionIds: ((j['collection_ids'] as List?) ?? const []).cast<String>(),
        files: ((j['files'] as List?) ?? const []).map((f) => FileMeta.fromJson(f as Map<String, dynamic>)).toList(),
        source: j['source'] as String? ?? 'android',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'url': url,
        'link': link?.toJson(),
        'location': location?.toJson(),
        'pinned': pinned,
        'starred': starred,
        'archived_at': archivedAt?.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'version': version,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'tags': tags.map((t) => t.toJson()).toList(),
        'collection_ids': collectionIds,
        'files': files.map((f) => f.toJson()).toList(),
        'source': source,
      };

  Item copyWith({
    String? title,
    String? body,
    bool? pinned,
    bool? starred,
    DateTime? archivedAt,
    bool clearArchived = false,
    DateTime? deletedAt,
    bool clearDeleted = false,
    List<FileMeta>? files,
  }) =>
      Item(
        id: id,
        type: type,
        title: title ?? this.title,
        body: body ?? this.body,
        url: url,
        link: link,
        location: location,
        pinned: pinned ?? this.pinned,
        starred: starred ?? this.starred,
        archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
        version: version,
        createdAt: createdAt,
        updatedAt: updatedAt,
        tags: tags,
        collectionIds: collectionIds,
        files: files ?? this.files,
        source: source,
      );
}

DateTime? _date(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

class Tag {
  Tag({required this.id, required this.name, required this.itemCount});
  final String id;
  final String name;
  final int itemCount;
  factory Tag.fromJson(Map<String, dynamic> j) =>
      Tag(id: j['id'] as String, name: j['name'] as String, itemCount: (j['item_count'] as num?)?.toInt() ?? 0);
}

class Collection {
  Collection({required this.id, required this.name, required this.itemCount});
  final String id;
  final String name;
  final int itemCount;
  factory Collection.fromJson(Map<String, dynamic> j) =>
      Collection(id: j['id'] as String, name: j['name'] as String, itemCount: (j['item_count'] as num?)?.toInt() ?? 0);
}

/// What a feed screen shows.
sealed class FeedView {
  const FeedView();
  String get title;
  bool includes(Item i);
}

class AllView extends FeedView {
  const AllView();
  @override
  String get title => 'Feed';
  @override
  bool includes(Item i) => !i.isTrashed && !i.isArchived;
}

class TypeView extends FeedView {
  const TypeView(this.type);
  final ItemType type;
  @override
  String get title => type.label;
  @override
  bool includes(Item i) => !i.isTrashed && !i.isArchived && i.type == type;
}

class FlagView extends FeedView {
  const FlagView(this.flag);
  final String flag; // pinned | starred | archived | trash
  @override
  String get title => switch (flag) { 'pinned' => 'Pinned', 'starred' => 'Starred', 'archived' => 'Archive', _ => 'Trash' };
  @override
  bool includes(Item i) => switch (flag) {
        'pinned' => !i.isTrashed && i.pinned,
        'starred' => !i.isTrashed && i.starred,
        'archived' => !i.isTrashed && i.isArchived,
        _ => i.isTrashed,
      };
}

class TagView extends FeedView {
  const TagView(this.id, this.name);
  final String id;
  final String name;
  @override
  String get title => '#$name';
  @override
  bool includes(Item i) => !i.isTrashed && !i.isArchived && i.tags.any((t) => t.id == id);
}

class CollectionView extends FeedView {
  const CollectionView(this.id, this.name);
  final String id;
  final String name;
  @override
  String get title => name;
  @override
  bool includes(Item i) => !i.isTrashed && !i.isArchived && i.collectionIds.contains(id);
}
