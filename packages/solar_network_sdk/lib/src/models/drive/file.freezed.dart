// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'file.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$UniversalFile {

 dynamic get data; UniversalFileType get type; bool get isLink; String? get displayName;
/// Create a copy of UniversalFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UniversalFileCopyWith<UniversalFile> get copyWith => _$UniversalFileCopyWithImpl<UniversalFile>(this as UniversalFile, _$identity);

  /// Serializes this UniversalFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as UniversalFile;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UniversalFile&&const DeepCollectionEquality().equals(other.data, _this.data)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.isLink, _this.isLink) || other.isLink == _this.isLink)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as UniversalFile;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.data),_this.type,_this.isLink,_this.displayName);
}

@override
String toString() {
  final _this = this as UniversalFile;
  return 'UniversalFile(data: ${_this.data}, type: ${_this.type}, isLink: ${_this.isLink}, displayName: ${_this.displayName})';
}


}

/// @nodoc
abstract mixin class $UniversalFileCopyWith<$Res>  {
  factory $UniversalFileCopyWith(UniversalFile value, $Res Function(UniversalFile) _then) = _$UniversalFileCopyWithImpl;
@useResult
$Res call({
 dynamic data, UniversalFileType type, bool isLink, String? displayName
});




}
/// @nodoc
class _$UniversalFileCopyWithImpl<$Res>
    implements $UniversalFileCopyWith<$Res> {
  _$UniversalFileCopyWithImpl(this._self, this._then);

  final UniversalFile _self;
  final $Res Function(UniversalFile) _then;

/// Create a copy of UniversalFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? data = freezed,Object? type = null,Object? isLink = null,Object? displayName = freezed,}) {
  return _then(UniversalFile(
data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as UniversalFileType,isLink: null == isLink ? _self.isLink : isLink // ignore: cast_nullable_to_non_nullable
as bool,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [UniversalFile].
extension UniversalFilePatterns on UniversalFile {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UniversalFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UniversalFile() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UniversalFile value)  $default,){
final _that = this;
switch (_that) {
case _UniversalFile():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UniversalFile value)?  $default,){
final _that = this;
switch (_that) {
case _UniversalFile() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( dynamic data,  UniversalFileType type,  bool isLink,  String? displayName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UniversalFile() when $default != null:
return $default(_that.data,_that.type,_that.isLink,_that.displayName);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( dynamic data,  UniversalFileType type,  bool isLink,  String? displayName)  $default,) {final _that = this;
switch (_that) {
case _UniversalFile():
return $default(_that.data,_that.type,_that.isLink,_that.displayName);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( dynamic data,  UniversalFileType type,  bool isLink,  String? displayName)?  $default,) {final _that = this;
switch (_that) {
case _UniversalFile() when $default != null:
return $default(_that.data,_that.type,_that.isLink,_that.displayName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _UniversalFile extends UniversalFile {
  const _UniversalFile({required this.data, required this.type, this.isLink = false, this.displayName}): super._();
  factory _UniversalFile.fromJson(Map<String, dynamic> json) => _$UniversalFileFromJson(json);

@override final  dynamic data;
@override final  UniversalFileType type;
@override@JsonKey() final  bool isLink;
@override final  String? displayName;

/// Create a copy of UniversalFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UniversalFileCopyWith<_UniversalFile> get copyWith => __$UniversalFileCopyWithImpl<_UniversalFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$UniversalFileToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UniversalFile&&const DeepCollectionEquality().equals(other.data, data)&&(identical(other.type, type) || other.type == type)&&(identical(other.isLink, isLink) || other.isLink == isLink)&&(identical(other.displayName, displayName) || other.displayName == displayName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(data),type,isLink,displayName);
}

@override
String toString() {
    return 'UniversalFile(data: $data, type: $type, isLink: $isLink, displayName: $displayName)';
}


}

/// @nodoc
abstract mixin class _$UniversalFileCopyWith<$Res> implements $UniversalFileCopyWith<$Res> {
  factory _$UniversalFileCopyWith(_UniversalFile value, $Res Function(_UniversalFile) _then) = __$UniversalFileCopyWithImpl;
@override @useResult
$Res call({
 dynamic data, UniversalFileType type, bool isLink, String? displayName
});




}
/// @nodoc
class __$UniversalFileCopyWithImpl<$Res>
    implements _$UniversalFileCopyWith<$Res> {
  __$UniversalFileCopyWithImpl(this._self, this._then);

  final _UniversalFile _self;
  final $Res Function(_UniversalFile) _then;

/// Create a copy of UniversalFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = freezed,Object? type = null,Object? isLink = null,Object? displayName = freezed,}) {
  return _then(_UniversalFile(
data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as dynamic,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as UniversalFileType,isLink: null == isLink ? _self.isLink : isLink // ignore: cast_nullable_to_non_nullable
as bool,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$SnFileReplica {

 String get id; String get objectId; String get poolId; SnFilePool? get pool; String get storageId; int get status; bool get isPrimary; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of SnFileReplica
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SnFileReplicaCopyWith<SnFileReplica> get copyWith => _$SnFileReplicaCopyWithImpl<SnFileReplica>(this as SnFileReplica, _$identity);

  /// Serializes this SnFileReplica to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SnFileReplica;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SnFileReplica&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.objectId, _this.objectId) || other.objectId == _this.objectId)&&(identical(other.poolId, _this.poolId) || other.poolId == _this.poolId)&&(identical(other.pool, _this.pool) || other.pool == _this.pool)&&(identical(other.storageId, _this.storageId) || other.storageId == _this.storageId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.isPrimary, _this.isPrimary) || other.isPrimary == _this.isPrimary)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SnFileReplica;
  return Object.hash(runtimeType,_this.id,_this.objectId,_this.poolId,_this.pool,_this.storageId,_this.status,_this.isPrimary,_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as SnFileReplica;
  return 'SnFileReplica(id: ${_this.id}, objectId: ${_this.objectId}, poolId: ${_this.poolId}, pool: ${_this.pool}, storageId: ${_this.storageId}, status: ${_this.status}, isPrimary: ${_this.isPrimary}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $SnFileReplicaCopyWith<$Res>  {
  factory $SnFileReplicaCopyWith(SnFileReplica value, $Res Function(SnFileReplica) _then) = _$SnFileReplicaCopyWithImpl;
@useResult
$Res call({
 String id, String objectId, String poolId, SnFilePool? pool, String storageId, int status, bool isPrimary, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});


$SnFilePoolCopyWith<$Res>? get pool;

}
/// @nodoc
class _$SnFileReplicaCopyWithImpl<$Res>
    implements $SnFileReplicaCopyWith<$Res> {
  _$SnFileReplicaCopyWithImpl(this._self, this._then);

  final SnFileReplica _self;
  final $Res Function(SnFileReplica) _then;

/// Create a copy of SnFileReplica
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? objectId = null,Object? poolId = null,Object? pool = freezed,Object? storageId = null,Object? status = null,Object? isPrimary = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(SnFileReplica(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,objectId: null == objectId ? _self.objectId : objectId // ignore: cast_nullable_to_non_nullable
as String,poolId: null == poolId ? _self.poolId : poolId // ignore: cast_nullable_to_non_nullable
as String,pool: freezed == pool ? _self.pool : pool // ignore: cast_nullable_to_non_nullable
as SnFilePool?,storageId: null == storageId ? _self.storageId : storageId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of SnFileReplica
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SnFilePoolCopyWith<$Res>? get pool {
    if (_self.pool == null) {
    return null;
  }

  return $SnFilePoolCopyWith<$Res>(_self.pool!, (value) {
    return _then(_self.copyWith(pool: value));
  });
}
}


/// Adds pattern-matching-related methods to [SnFileReplica].
extension SnFileReplicaPatterns on SnFileReplica {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SnFileReplica value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SnFileReplica() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SnFileReplica value)  $default,){
final _that = this;
switch (_that) {
case _SnFileReplica():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SnFileReplica value)?  $default,){
final _that = this;
switch (_that) {
case _SnFileReplica() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String objectId,  String poolId,  SnFilePool? pool,  String storageId,  int status,  bool isPrimary,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SnFileReplica() when $default != null:
return $default(_that.id,_that.objectId,_that.poolId,_that.pool,_that.storageId,_that.status,_that.isPrimary,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String objectId,  String poolId,  SnFilePool? pool,  String storageId,  int status,  bool isPrimary,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _SnFileReplica():
return $default(_that.id,_that.objectId,_that.poolId,_that.pool,_that.storageId,_that.status,_that.isPrimary,_that.createdAt,_that.updatedAt,_that.deletedAt);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String objectId,  String poolId,  SnFilePool? pool,  String storageId,  int status,  bool isPrimary,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _SnFileReplica() when $default != null:
return $default(_that.id,_that.objectId,_that.poolId,_that.pool,_that.storageId,_that.status,_that.isPrimary,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SnFileReplica implements SnFileReplica {
  const _SnFileReplica({required this.id, required this.objectId, required this.poolId, required this.pool, required this.storageId, required this.status, required this.isPrimary, required this.createdAt, required this.updatedAt, required this.deletedAt});
  factory _SnFileReplica.fromJson(Map<String, dynamic> json) => _$SnFileReplicaFromJson(json);

@override final  String id;
@override final  String objectId;
@override final  String poolId;
@override final  SnFilePool? pool;
@override final  String storageId;
@override final  int status;
@override final  bool isPrimary;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of SnFileReplica
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SnFileReplicaCopyWith<_SnFileReplica> get copyWith => __$SnFileReplicaCopyWithImpl<_SnFileReplica>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SnFileReplicaToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SnFileReplica&&(identical(other.id, id) || other.id == id)&&(identical(other.objectId, objectId) || other.objectId == objectId)&&(identical(other.poolId, poolId) || other.poolId == poolId)&&(identical(other.pool, pool) || other.pool == pool)&&(identical(other.storageId, storageId) || other.storageId == storageId)&&(identical(other.status, status) || other.status == status)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,objectId,poolId,pool,storageId,status,isPrimary,createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'SnFileReplica(id: $id, objectId: $objectId, poolId: $poolId, pool: $pool, storageId: $storageId, status: $status, isPrimary: $isPrimary, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$SnFileReplicaCopyWith<$Res> implements $SnFileReplicaCopyWith<$Res> {
  factory _$SnFileReplicaCopyWith(_SnFileReplica value, $Res Function(_SnFileReplica) _then) = __$SnFileReplicaCopyWithImpl;
@override @useResult
$Res call({
 String id, String objectId, String poolId, SnFilePool? pool, String storageId, int status, bool isPrimary, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});


@override $SnFilePoolCopyWith<$Res>? get pool;

}
/// @nodoc
class __$SnFileReplicaCopyWithImpl<$Res>
    implements _$SnFileReplicaCopyWith<$Res> {
  __$SnFileReplicaCopyWithImpl(this._self, this._then);

  final _SnFileReplica _self;
  final $Res Function(_SnFileReplica) _then;

/// Create a copy of SnFileReplica
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? objectId = null,Object? poolId = null,Object? pool = freezed,Object? storageId = null,Object? status = null,Object? isPrimary = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_SnFileReplica(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,objectId: null == objectId ? _self.objectId : objectId // ignore: cast_nullable_to_non_nullable
as String,poolId: null == poolId ? _self.poolId : poolId // ignore: cast_nullable_to_non_nullable
as String,pool: freezed == pool ? _self.pool : pool // ignore: cast_nullable_to_non_nullable
as SnFilePool?,storageId: null == storageId ? _self.storageId : storageId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of SnFileReplica
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SnFilePoolCopyWith<$Res>? get pool {
    if (_self.pool == null) {
    return null;
  }

  return $SnFilePoolCopyWith<$Res>(_self.pool!, (value) {
    return _then(_self.copyWith(pool: value));
  });
}
}


/// @nodoc
mixin _$SnCloudFileObject {

 String get id; int get size; Map<String, dynamic>? get meta; String? get mimeType; String? get hash; bool get hasCompression; bool get hasThumbnail; List<SnFileReplica> get fileReplicas; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of SnCloudFileObject
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SnCloudFileObjectCopyWith<SnCloudFileObject> get copyWith => _$SnCloudFileObjectCopyWithImpl<SnCloudFileObject>(this as SnCloudFileObject, _$identity);

  /// Serializes this SnCloudFileObject to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SnCloudFileObject;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SnCloudFileObject&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.size, _this.size) || other.size == _this.size)&&const DeepCollectionEquality().equals(other.meta, _this.meta)&&(identical(other.mimeType, _this.mimeType) || other.mimeType == _this.mimeType)&&(identical(other.hash, _this.hash) || other.hash == _this.hash)&&(identical(other.hasCompression, _this.hasCompression) || other.hasCompression == _this.hasCompression)&&(identical(other.hasThumbnail, _this.hasThumbnail) || other.hasThumbnail == _this.hasThumbnail)&&const DeepCollectionEquality().equals(other.fileReplicas, _this.fileReplicas)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SnCloudFileObject;
  return Object.hash(runtimeType,_this.id,_this.size,const DeepCollectionEquality().hash(_this.meta),_this.mimeType,_this.hash,_this.hasCompression,_this.hasThumbnail,const DeepCollectionEquality().hash(_this.fileReplicas),_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as SnCloudFileObject;
  return 'SnCloudFileObject(id: ${_this.id}, size: ${_this.size}, meta: ${_this.meta}, mimeType: ${_this.mimeType}, hash: ${_this.hash}, hasCompression: ${_this.hasCompression}, hasThumbnail: ${_this.hasThumbnail}, fileReplicas: ${_this.fileReplicas}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $SnCloudFileObjectCopyWith<$Res>  {
  factory $SnCloudFileObjectCopyWith(SnCloudFileObject value, $Res Function(SnCloudFileObject) _then) = _$SnCloudFileObjectCopyWithImpl;
@useResult
$Res call({
 String id, int size, Map<String, dynamic>? meta, String? mimeType, String? hash, bool hasCompression, bool hasThumbnail, List<SnFileReplica> fileReplicas, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$SnCloudFileObjectCopyWithImpl<$Res>
    implements $SnCloudFileObjectCopyWith<$Res> {
  _$SnCloudFileObjectCopyWithImpl(this._self, this._then);

  final SnCloudFileObject _self;
  final $Res Function(SnCloudFileObject) _then;

/// Create a copy of SnCloudFileObject
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? size = null,Object? meta = freezed,Object? mimeType = freezed,Object? hash = freezed,Object? hasCompression = null,Object? hasThumbnail = null,Object? fileReplicas = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(SnCloudFileObject(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,hash: freezed == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String?,hasCompression: null == hasCompression ? _self.hasCompression : hasCompression // ignore: cast_nullable_to_non_nullable
as bool,hasThumbnail: null == hasThumbnail ? _self.hasThumbnail : hasThumbnail // ignore: cast_nullable_to_non_nullable
as bool,fileReplicas: null == fileReplicas ? _self.fileReplicas : fileReplicas // ignore: cast_nullable_to_non_nullable
as List<SnFileReplica>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [SnCloudFileObject].
extension SnCloudFileObjectPatterns on SnCloudFileObject {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SnCloudFileObject value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SnCloudFileObject() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SnCloudFileObject value)  $default,){
final _that = this;
switch (_that) {
case _SnCloudFileObject():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SnCloudFileObject value)?  $default,){
final _that = this;
switch (_that) {
case _SnCloudFileObject() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int size,  Map<String, dynamic>? meta,  String? mimeType,  String? hash,  bool hasCompression,  bool hasThumbnail,  List<SnFileReplica> fileReplicas,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SnCloudFileObject() when $default != null:
return $default(_that.id,_that.size,_that.meta,_that.mimeType,_that.hash,_that.hasCompression,_that.hasThumbnail,_that.fileReplicas,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int size,  Map<String, dynamic>? meta,  String? mimeType,  String? hash,  bool hasCompression,  bool hasThumbnail,  List<SnFileReplica> fileReplicas,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _SnCloudFileObject():
return $default(_that.id,_that.size,_that.meta,_that.mimeType,_that.hash,_that.hasCompression,_that.hasThumbnail,_that.fileReplicas,_that.createdAt,_that.updatedAt,_that.deletedAt);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int size,  Map<String, dynamic>? meta,  String? mimeType,  String? hash,  bool hasCompression,  bool hasThumbnail,  List<SnFileReplica> fileReplicas,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _SnCloudFileObject() when $default != null:
return $default(_that.id,_that.size,_that.meta,_that.mimeType,_that.hash,_that.hasCompression,_that.hasThumbnail,_that.fileReplicas,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SnCloudFileObject implements SnCloudFileObject {
  const _SnCloudFileObject({required this.id, required this.size, required  Map<String, dynamic>? meta, required this.mimeType, required this.hash, required this.hasCompression, required this.hasThumbnail, required  List<SnFileReplica> fileReplicas, required this.createdAt, required this.updatedAt, required this.deletedAt}): _meta = meta,_fileReplicas = fileReplicas;
  factory _SnCloudFileObject.fromJson(Map<String, dynamic> json) => _$SnCloudFileObjectFromJson(json);

@override final  String id;
@override final  int size;
 final  Map<String, dynamic>? _meta;
@override Map<String, dynamic>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  String? mimeType;
@override final  String? hash;
@override final  bool hasCompression;
@override final  bool hasThumbnail;
 final  List<SnFileReplica> _fileReplicas;
@override List<SnFileReplica> get fileReplicas {
  if (_fileReplicas is EqualUnmodifiableListView) return _fileReplicas;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_fileReplicas);
}

@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of SnCloudFileObject
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SnCloudFileObjectCopyWith<_SnCloudFileObject> get copyWith => __$SnCloudFileObjectCopyWithImpl<_SnCloudFileObject>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SnCloudFileObjectToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SnCloudFileObject&&(identical(other.id, id) || other.id == id)&&(identical(other.size, size) || other.size == size)&&const DeepCollectionEquality().equals(other.meta, _meta)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.hash, hash) || other.hash == hash)&&(identical(other.hasCompression, hasCompression) || other.hasCompression == hasCompression)&&(identical(other.hasThumbnail, hasThumbnail) || other.hasThumbnail == hasThumbnail)&&const DeepCollectionEquality().equals(other.fileReplicas, _fileReplicas)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,size,const DeepCollectionEquality().hash(_meta),mimeType,hash,hasCompression,hasThumbnail,const DeepCollectionEquality().hash(_fileReplicas),createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'SnCloudFileObject(id: $id, size: $size, meta: $meta, mimeType: $mimeType, hash: $hash, hasCompression: $hasCompression, hasThumbnail: $hasThumbnail, fileReplicas: $fileReplicas, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$SnCloudFileObjectCopyWith<$Res> implements $SnCloudFileObjectCopyWith<$Res> {
  factory _$SnCloudFileObjectCopyWith(_SnCloudFileObject value, $Res Function(_SnCloudFileObject) _then) = __$SnCloudFileObjectCopyWithImpl;
@override @useResult
$Res call({
 String id, int size, Map<String, dynamic>? meta, String? mimeType, String? hash, bool hasCompression, bool hasThumbnail, List<SnFileReplica> fileReplicas, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$SnCloudFileObjectCopyWithImpl<$Res>
    implements _$SnCloudFileObjectCopyWith<$Res> {
  __$SnCloudFileObjectCopyWithImpl(this._self, this._then);

  final _SnCloudFileObject _self;
  final $Res Function(_SnCloudFileObject) _then;

/// Create a copy of SnCloudFileObject
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? size = null,Object? meta = freezed,Object? mimeType = freezed,Object? hash = freezed,Object? hasCompression = null,Object? hasThumbnail = null,Object? fileReplicas = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_SnCloudFileObject(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,hash: freezed == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String?,hasCompression: null == hasCompression ? _self.hasCompression : hasCompression // ignore: cast_nullable_to_non_nullable
as bool,hasThumbnail: null == hasThumbnail ? _self.hasThumbnail : hasThumbnail // ignore: cast_nullable_to_non_nullable
as bool,fileReplicas: null == fileReplicas ? _self._fileReplicas : fileReplicas // ignore: cast_nullable_to_non_nullable
as List<SnFileReplica>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$SnCloudFile {

 String get id; String get accountId; String? get description; bool get indexed; bool get isFolder; bool get isMarkedRecycle; String get name; SnCloudFileObject? get object; String? get objectId; String? get parentId; String get resourceIdentifier; String? get storageId;@JsonKey(fromJson: _nonBlankUrl) String? get storageUrl; String get mimeType; String? get applicationType; String? get usage; List<int> get sensitiveMarks; Map<String, dynamic> get fileMeta; Map<String, dynamic> get userMeta; List<SnCloudFile> get children;@JsonKey(name: 'children_count') int get childrenCount;@JsonKey(name: 'permission_status') SnFilePermissionStatus? get permissionStatus; DateTime? get uploadedAt; DateTime? get expiredAt; DateTime get updatedAt; DateTime get createdAt; DateTime? get deletedAt;
/// Create a copy of SnCloudFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SnCloudFileCopyWith<SnCloudFile> get copyWith => _$SnCloudFileCopyWithImpl<SnCloudFile>(this as SnCloudFile, _$identity);

  /// Serializes this SnCloudFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SnCloudFile;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SnCloudFile&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.indexed, _this.indexed) || other.indexed == _this.indexed)&&(identical(other.isFolder, _this.isFolder) || other.isFolder == _this.isFolder)&&(identical(other.isMarkedRecycle, _this.isMarkedRecycle) || other.isMarkedRecycle == _this.isMarkedRecycle)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.object, _this.object) || other.object == _this.object)&&(identical(other.objectId, _this.objectId) || other.objectId == _this.objectId)&&(identical(other.parentId, _this.parentId) || other.parentId == _this.parentId)&&(identical(other.resourceIdentifier, _this.resourceIdentifier) || other.resourceIdentifier == _this.resourceIdentifier)&&(identical(other.storageId, _this.storageId) || other.storageId == _this.storageId)&&(identical(other.storageUrl, _this.storageUrl) || other.storageUrl == _this.storageUrl)&&(identical(other.mimeType, _this.mimeType) || other.mimeType == _this.mimeType)&&(identical(other.applicationType, _this.applicationType) || other.applicationType == _this.applicationType)&&(identical(other.usage, _this.usage) || other.usage == _this.usage)&&const DeepCollectionEquality().equals(other.sensitiveMarks, _this.sensitiveMarks)&&const DeepCollectionEquality().equals(other.fileMeta, _this.fileMeta)&&const DeepCollectionEquality().equals(other.userMeta, _this.userMeta)&&const DeepCollectionEquality().equals(other.children, _this.children)&&(identical(other.childrenCount, _this.childrenCount) || other.childrenCount == _this.childrenCount)&&(identical(other.permissionStatus, _this.permissionStatus) || other.permissionStatus == _this.permissionStatus)&&(identical(other.uploadedAt, _this.uploadedAt) || other.uploadedAt == _this.uploadedAt)&&(identical(other.expiredAt, _this.expiredAt) || other.expiredAt == _this.expiredAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SnCloudFile;
  return Object.hashAll([runtimeType,_this.id,_this.accountId,_this.description,_this.indexed,_this.isFolder,_this.isMarkedRecycle,_this.name,_this.object,_this.objectId,_this.parentId,_this.resourceIdentifier,_this.storageId,_this.storageUrl,_this.mimeType,_this.applicationType,_this.usage,const DeepCollectionEquality().hash(_this.sensitiveMarks),const DeepCollectionEquality().hash(_this.fileMeta),const DeepCollectionEquality().hash(_this.userMeta),const DeepCollectionEquality().hash(_this.children),_this.childrenCount,_this.permissionStatus,_this.uploadedAt,_this.expiredAt,_this.updatedAt,_this.createdAt,_this.deletedAt]);
}

@override
String toString() {
  final _this = this as SnCloudFile;
  return 'SnCloudFile(id: ${_this.id}, accountId: ${_this.accountId}, description: ${_this.description}, indexed: ${_this.indexed}, isFolder: ${_this.isFolder}, isMarkedRecycle: ${_this.isMarkedRecycle}, name: ${_this.name}, object: ${_this.object}, objectId: ${_this.objectId}, parentId: ${_this.parentId}, resourceIdentifier: ${_this.resourceIdentifier}, storageId: ${_this.storageId}, storageUrl: ${_this.storageUrl}, mimeType: ${_this.mimeType}, applicationType: ${_this.applicationType}, usage: ${_this.usage}, sensitiveMarks: ${_this.sensitiveMarks}, fileMeta: ${_this.fileMeta}, userMeta: ${_this.userMeta}, children: ${_this.children}, childrenCount: ${_this.childrenCount}, permissionStatus: ${_this.permissionStatus}, uploadedAt: ${_this.uploadedAt}, expiredAt: ${_this.expiredAt}, updatedAt: ${_this.updatedAt}, createdAt: ${_this.createdAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $SnCloudFileCopyWith<$Res>  {
  factory $SnCloudFileCopyWith(SnCloudFile value, $Res Function(SnCloudFile) _then) = _$SnCloudFileCopyWithImpl;
@useResult
$Res call({
 String id, String accountId, String? description, bool indexed, bool isFolder, bool isMarkedRecycle, String name, SnCloudFileObject? object, String? objectId, String? parentId, String resourceIdentifier, String? storageId,@JsonKey(fromJson: _nonBlankUrl) String? storageUrl, String mimeType, String? applicationType, String? usage, List<int> sensitiveMarks, Map<String, dynamic> fileMeta, Map<String, dynamic> userMeta, List<SnCloudFile> children,@JsonKey(name: 'children_count') int childrenCount,@JsonKey(name: 'permission_status') SnFilePermissionStatus? permissionStatus, DateTime? uploadedAt, DateTime? expiredAt, DateTime updatedAt, DateTime createdAt, DateTime? deletedAt
});


$SnCloudFileObjectCopyWith<$Res>? get object;$SnFilePermissionStatusCopyWith<$Res>? get permissionStatus;

}
/// @nodoc
class _$SnCloudFileCopyWithImpl<$Res>
    implements $SnCloudFileCopyWith<$Res> {
  _$SnCloudFileCopyWithImpl(this._self, this._then);

  final SnCloudFile _self;
  final $Res Function(SnCloudFile) _then;

/// Create a copy of SnCloudFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? accountId = null,Object? description = freezed,Object? indexed = null,Object? isFolder = null,Object? isMarkedRecycle = null,Object? name = null,Object? object = freezed,Object? objectId = freezed,Object? parentId = freezed,Object? resourceIdentifier = null,Object? storageId = freezed,Object? storageUrl = freezed,Object? mimeType = null,Object? applicationType = freezed,Object? usage = freezed,Object? sensitiveMarks = null,Object? fileMeta = null,Object? userMeta = null,Object? children = null,Object? childrenCount = null,Object? permissionStatus = freezed,Object? uploadedAt = freezed,Object? expiredAt = freezed,Object? updatedAt = null,Object? createdAt = null,Object? deletedAt = freezed,}) {
  return _then(SnCloudFile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,indexed: null == indexed ? _self.indexed : indexed // ignore: cast_nullable_to_non_nullable
as bool,isFolder: null == isFolder ? _self.isFolder : isFolder // ignore: cast_nullable_to_non_nullable
as bool,isMarkedRecycle: null == isMarkedRecycle ? _self.isMarkedRecycle : isMarkedRecycle // ignore: cast_nullable_to_non_nullable
as bool,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,object: freezed == object ? _self.object : object // ignore: cast_nullable_to_non_nullable
as SnCloudFileObject?,objectId: freezed == objectId ? _self.objectId : objectId // ignore: cast_nullable_to_non_nullable
as String?,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,resourceIdentifier: null == resourceIdentifier ? _self.resourceIdentifier : resourceIdentifier // ignore: cast_nullable_to_non_nullable
as String,storageId: freezed == storageId ? _self.storageId : storageId // ignore: cast_nullable_to_non_nullable
as String?,storageUrl: freezed == storageUrl ? _self.storageUrl : storageUrl // ignore: cast_nullable_to_non_nullable
as String?,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,applicationType: freezed == applicationType ? _self.applicationType : applicationType // ignore: cast_nullable_to_non_nullable
as String?,usage: freezed == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as String?,sensitiveMarks: null == sensitiveMarks ? _self.sensitiveMarks : sensitiveMarks // ignore: cast_nullable_to_non_nullable
as List<int>,fileMeta: null == fileMeta ? _self.fileMeta : fileMeta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,userMeta: null == userMeta ? _self.userMeta : userMeta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,children: null == children ? _self.children : children // ignore: cast_nullable_to_non_nullable
as List<SnCloudFile>,childrenCount: null == childrenCount ? _self.childrenCount : childrenCount // ignore: cast_nullable_to_non_nullable
as int,permissionStatus: freezed == permissionStatus ? _self.permissionStatus : permissionStatus // ignore: cast_nullable_to_non_nullable
as SnFilePermissionStatus?,uploadedAt: freezed == uploadedAt ? _self.uploadedAt : uploadedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,expiredAt: freezed == expiredAt ? _self.expiredAt : expiredAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of SnCloudFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SnCloudFileObjectCopyWith<$Res>? get object {
    if (_self.object == null) {
    return null;
  }

  return $SnCloudFileObjectCopyWith<$Res>(_self.object!, (value) {
    return _then(_self.copyWith(object: value));
  });
}/// Create a copy of SnCloudFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SnFilePermissionStatusCopyWith<$Res>? get permissionStatus {
    if (_self.permissionStatus == null) {
    return null;
  }

  return $SnFilePermissionStatusCopyWith<$Res>(_self.permissionStatus!, (value) {
    return _then(_self.copyWith(permissionStatus: value));
  });
}
}


/// Adds pattern-matching-related methods to [SnCloudFile].
extension SnCloudFilePatterns on SnCloudFile {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SnCloudFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SnCloudFile() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SnCloudFile value)  $default,){
final _that = this;
switch (_that) {
case _SnCloudFile():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SnCloudFile value)?  $default,){
final _that = this;
switch (_that) {
case _SnCloudFile() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String accountId,  String? description,  bool indexed,  bool isFolder,  bool isMarkedRecycle,  String name,  SnCloudFileObject? object,  String? objectId,  String? parentId,  String resourceIdentifier,  String? storageId, @JsonKey(fromJson: _nonBlankUrl)  String? storageUrl,  String mimeType,  String? applicationType,  String? usage,  List<int> sensitiveMarks,  Map<String, dynamic> fileMeta,  Map<String, dynamic> userMeta,  List<SnCloudFile> children, @JsonKey(name: 'children_count')  int childrenCount, @JsonKey(name: 'permission_status')  SnFilePermissionStatus? permissionStatus,  DateTime? uploadedAt,  DateTime? expiredAt,  DateTime updatedAt,  DateTime createdAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SnCloudFile() when $default != null:
return $default(_that.id,_that.accountId,_that.description,_that.indexed,_that.isFolder,_that.isMarkedRecycle,_that.name,_that.object,_that.objectId,_that.parentId,_that.resourceIdentifier,_that.storageId,_that.storageUrl,_that.mimeType,_that.applicationType,_that.usage,_that.sensitiveMarks,_that.fileMeta,_that.userMeta,_that.children,_that.childrenCount,_that.permissionStatus,_that.uploadedAt,_that.expiredAt,_that.updatedAt,_that.createdAt,_that.deletedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String accountId,  String? description,  bool indexed,  bool isFolder,  bool isMarkedRecycle,  String name,  SnCloudFileObject? object,  String? objectId,  String? parentId,  String resourceIdentifier,  String? storageId, @JsonKey(fromJson: _nonBlankUrl)  String? storageUrl,  String mimeType,  String? applicationType,  String? usage,  List<int> sensitiveMarks,  Map<String, dynamic> fileMeta,  Map<String, dynamic> userMeta,  List<SnCloudFile> children, @JsonKey(name: 'children_count')  int childrenCount, @JsonKey(name: 'permission_status')  SnFilePermissionStatus? permissionStatus,  DateTime? uploadedAt,  DateTime? expiredAt,  DateTime updatedAt,  DateTime createdAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _SnCloudFile():
return $default(_that.id,_that.accountId,_that.description,_that.indexed,_that.isFolder,_that.isMarkedRecycle,_that.name,_that.object,_that.objectId,_that.parentId,_that.resourceIdentifier,_that.storageId,_that.storageUrl,_that.mimeType,_that.applicationType,_that.usage,_that.sensitiveMarks,_that.fileMeta,_that.userMeta,_that.children,_that.childrenCount,_that.permissionStatus,_that.uploadedAt,_that.expiredAt,_that.updatedAt,_that.createdAt,_that.deletedAt);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String accountId,  String? description,  bool indexed,  bool isFolder,  bool isMarkedRecycle,  String name,  SnCloudFileObject? object,  String? objectId,  String? parentId,  String resourceIdentifier,  String? storageId, @JsonKey(fromJson: _nonBlankUrl)  String? storageUrl,  String mimeType,  String? applicationType,  String? usage,  List<int> sensitiveMarks,  Map<String, dynamic> fileMeta,  Map<String, dynamic> userMeta,  List<SnCloudFile> children, @JsonKey(name: 'children_count')  int childrenCount, @JsonKey(name: 'permission_status')  SnFilePermissionStatus? permissionStatus,  DateTime? uploadedAt,  DateTime? expiredAt,  DateTime updatedAt,  DateTime createdAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _SnCloudFile() when $default != null:
return $default(_that.id,_that.accountId,_that.description,_that.indexed,_that.isFolder,_that.isMarkedRecycle,_that.name,_that.object,_that.objectId,_that.parentId,_that.resourceIdentifier,_that.storageId,_that.storageUrl,_that.mimeType,_that.applicationType,_that.usage,_that.sensitiveMarks,_that.fileMeta,_that.userMeta,_that.children,_that.childrenCount,_that.permissionStatus,_that.uploadedAt,_that.expiredAt,_that.updatedAt,_that.createdAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SnCloudFile extends SnCloudFile {
  const _SnCloudFile({required this.id, required this.accountId, required this.description, required this.indexed, required this.isFolder, required this.isMarkedRecycle, required this.name, required this.object, required this.objectId, required this.parentId, required this.resourceIdentifier, required this.storageId, @JsonKey(fromJson: _nonBlankUrl) required this.storageUrl, required this.mimeType, required this.applicationType, required this.usage,  List<int> sensitiveMarks = const [],  Map<String, dynamic> fileMeta = const {},  Map<String, dynamic> userMeta = const {},  List<SnCloudFile> children = const [], @JsonKey(name: 'children_count') this.childrenCount = 0, @JsonKey(name: 'permission_status') required this.permissionStatus, required this.uploadedAt, required this.expiredAt, required this.updatedAt, required this.createdAt, required this.deletedAt}): _sensitiveMarks = sensitiveMarks,_fileMeta = fileMeta,_userMeta = userMeta,_children = children,super._();
  factory _SnCloudFile.fromJson(Map<String, dynamic> json) => _$SnCloudFileFromJson(json);

@override final  String id;
@override final  String accountId;
@override final  String? description;
@override final  bool indexed;
@override final  bool isFolder;
@override final  bool isMarkedRecycle;
@override final  String name;
@override final  SnCloudFileObject? object;
@override final  String? objectId;
@override final  String? parentId;
@override final  String resourceIdentifier;
@override final  String? storageId;
@override@JsonKey(fromJson: _nonBlankUrl) final  String? storageUrl;
@override final  String mimeType;
@override final  String? applicationType;
@override final  String? usage;
 final  List<int> _sensitiveMarks;
@override@JsonKey() List<int> get sensitiveMarks {
  if (_sensitiveMarks is EqualUnmodifiableListView) return _sensitiveMarks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sensitiveMarks);
}

 final  Map<String, dynamic> _fileMeta;
@override@JsonKey() Map<String, dynamic> get fileMeta {
  if (_fileMeta is EqualUnmodifiableMapView) return _fileMeta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_fileMeta);
}

 final  Map<String, dynamic> _userMeta;
@override@JsonKey() Map<String, dynamic> get userMeta {
  if (_userMeta is EqualUnmodifiableMapView) return _userMeta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_userMeta);
}

 final  List<SnCloudFile> _children;
@override@JsonKey() List<SnCloudFile> get children {
  if (_children is EqualUnmodifiableListView) return _children;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_children);
}

@override@JsonKey(name: 'children_count') final  int childrenCount;
@override@JsonKey(name: 'permission_status') final  SnFilePermissionStatus? permissionStatus;
@override final  DateTime? uploadedAt;
@override final  DateTime? expiredAt;
@override final  DateTime updatedAt;
@override final  DateTime createdAt;
@override final  DateTime? deletedAt;

/// Create a copy of SnCloudFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SnCloudFileCopyWith<_SnCloudFile> get copyWith => __$SnCloudFileCopyWithImpl<_SnCloudFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SnCloudFileToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SnCloudFile&&(identical(other.id, id) || other.id == id)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.description, description) || other.description == description)&&(identical(other.indexed, indexed) || other.indexed == indexed)&&(identical(other.isFolder, isFolder) || other.isFolder == isFolder)&&(identical(other.isMarkedRecycle, isMarkedRecycle) || other.isMarkedRecycle == isMarkedRecycle)&&(identical(other.name, name) || other.name == name)&&(identical(other.object, object) || other.object == object)&&(identical(other.objectId, objectId) || other.objectId == objectId)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.resourceIdentifier, resourceIdentifier) || other.resourceIdentifier == resourceIdentifier)&&(identical(other.storageId, storageId) || other.storageId == storageId)&&(identical(other.storageUrl, storageUrl) || other.storageUrl == storageUrl)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.applicationType, applicationType) || other.applicationType == applicationType)&&(identical(other.usage, usage) || other.usage == usage)&&const DeepCollectionEquality().equals(other.sensitiveMarks, _sensitiveMarks)&&const DeepCollectionEquality().equals(other.fileMeta, _fileMeta)&&const DeepCollectionEquality().equals(other.userMeta, _userMeta)&&const DeepCollectionEquality().equals(other.children, _children)&&(identical(other.childrenCount, childrenCount) || other.childrenCount == childrenCount)&&(identical(other.permissionStatus, permissionStatus) || other.permissionStatus == permissionStatus)&&(identical(other.uploadedAt, uploadedAt) || other.uploadedAt == uploadedAt)&&(identical(other.expiredAt, expiredAt) || other.expiredAt == expiredAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,accountId,description,indexed,isFolder,isMarkedRecycle,name,object,objectId,parentId,resourceIdentifier,storageId,storageUrl,mimeType,applicationType,usage,const DeepCollectionEquality().hash(_sensitiveMarks),const DeepCollectionEquality().hash(_fileMeta),const DeepCollectionEquality().hash(_userMeta),const DeepCollectionEquality().hash(_children),childrenCount,permissionStatus,uploadedAt,expiredAt,updatedAt,createdAt,deletedAt]);
}

@override
String toString() {
    return 'SnCloudFile(id: $id, accountId: $accountId, description: $description, indexed: $indexed, isFolder: $isFolder, isMarkedRecycle: $isMarkedRecycle, name: $name, object: $object, objectId: $objectId, parentId: $parentId, resourceIdentifier: $resourceIdentifier, storageId: $storageId, storageUrl: $storageUrl, mimeType: $mimeType, applicationType: $applicationType, usage: $usage, sensitiveMarks: $sensitiveMarks, fileMeta: $fileMeta, userMeta: $userMeta, children: $children, childrenCount: $childrenCount, permissionStatus: $permissionStatus, uploadedAt: $uploadedAt, expiredAt: $expiredAt, updatedAt: $updatedAt, createdAt: $createdAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$SnCloudFileCopyWith<$Res> implements $SnCloudFileCopyWith<$Res> {
  factory _$SnCloudFileCopyWith(_SnCloudFile value, $Res Function(_SnCloudFile) _then) = __$SnCloudFileCopyWithImpl;
@override @useResult
$Res call({
 String id, String accountId, String? description, bool indexed, bool isFolder, bool isMarkedRecycle, String name, SnCloudFileObject? object, String? objectId, String? parentId, String resourceIdentifier, String? storageId,@JsonKey(fromJson: _nonBlankUrl) String? storageUrl, String mimeType, String? applicationType, String? usage, List<int> sensitiveMarks, Map<String, dynamic> fileMeta, Map<String, dynamic> userMeta, List<SnCloudFile> children,@JsonKey(name: 'children_count') int childrenCount,@JsonKey(name: 'permission_status') SnFilePermissionStatus? permissionStatus, DateTime? uploadedAt, DateTime? expiredAt, DateTime updatedAt, DateTime createdAt, DateTime? deletedAt
});


@override $SnCloudFileObjectCopyWith<$Res>? get object;@override $SnFilePermissionStatusCopyWith<$Res>? get permissionStatus;

}
/// @nodoc
class __$SnCloudFileCopyWithImpl<$Res>
    implements _$SnCloudFileCopyWith<$Res> {
  __$SnCloudFileCopyWithImpl(this._self, this._then);

  final _SnCloudFile _self;
  final $Res Function(_SnCloudFile) _then;

/// Create a copy of SnCloudFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? accountId = null,Object? description = freezed,Object? indexed = null,Object? isFolder = null,Object? isMarkedRecycle = null,Object? name = null,Object? object = freezed,Object? objectId = freezed,Object? parentId = freezed,Object? resourceIdentifier = null,Object? storageId = freezed,Object? storageUrl = freezed,Object? mimeType = null,Object? applicationType = freezed,Object? usage = freezed,Object? sensitiveMarks = null,Object? fileMeta = null,Object? userMeta = null,Object? children = null,Object? childrenCount = null,Object? permissionStatus = freezed,Object? uploadedAt = freezed,Object? expiredAt = freezed,Object? updatedAt = null,Object? createdAt = null,Object? deletedAt = freezed,}) {
  return _then(_SnCloudFile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,indexed: null == indexed ? _self.indexed : indexed // ignore: cast_nullable_to_non_nullable
as bool,isFolder: null == isFolder ? _self.isFolder : isFolder // ignore: cast_nullable_to_non_nullable
as bool,isMarkedRecycle: null == isMarkedRecycle ? _self.isMarkedRecycle : isMarkedRecycle // ignore: cast_nullable_to_non_nullable
as bool,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,object: freezed == object ? _self.object : object // ignore: cast_nullable_to_non_nullable
as SnCloudFileObject?,objectId: freezed == objectId ? _self.objectId : objectId // ignore: cast_nullable_to_non_nullable
as String?,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,resourceIdentifier: null == resourceIdentifier ? _self.resourceIdentifier : resourceIdentifier // ignore: cast_nullable_to_non_nullable
as String,storageId: freezed == storageId ? _self.storageId : storageId // ignore: cast_nullable_to_non_nullable
as String?,storageUrl: freezed == storageUrl ? _self.storageUrl : storageUrl // ignore: cast_nullable_to_non_nullable
as String?,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,applicationType: freezed == applicationType ? _self.applicationType : applicationType // ignore: cast_nullable_to_non_nullable
as String?,usage: freezed == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as String?,sensitiveMarks: null == sensitiveMarks ? _self._sensitiveMarks : sensitiveMarks // ignore: cast_nullable_to_non_nullable
as List<int>,fileMeta: null == fileMeta ? _self._fileMeta : fileMeta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,userMeta: null == userMeta ? _self._userMeta : userMeta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,children: null == children ? _self._children : children // ignore: cast_nullable_to_non_nullable
as List<SnCloudFile>,childrenCount: null == childrenCount ? _self.childrenCount : childrenCount // ignore: cast_nullable_to_non_nullable
as int,permissionStatus: freezed == permissionStatus ? _self.permissionStatus : permissionStatus // ignore: cast_nullable_to_non_nullable
as SnFilePermissionStatus?,uploadedAt: freezed == uploadedAt ? _self.uploadedAt : uploadedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,expiredAt: freezed == expiredAt ? _self.expiredAt : expiredAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of SnCloudFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SnCloudFileObjectCopyWith<$Res>? get object {
    if (_self.object == null) {
    return null;
  }

  return $SnCloudFileObjectCopyWith<$Res>(_self.object!, (value) {
    return _then(_self.copyWith(object: value));
  });
}/// Create a copy of SnCloudFile
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SnFilePermissionStatusCopyWith<$Res>? get permissionStatus {
    if (_self.permissionStatus == null) {
    return null;
  }

  return $SnFilePermissionStatusCopyWith<$Res>(_self.permissionStatus!, (value) {
    return _then(_self.copyWith(permissionStatus: value));
  });
}
}


/// @nodoc
mixin _$SnCloudFileReference {

 String get id; String get name; Map<String, dynamic> get fileMeta; Map<String, dynamic> get userMeta; List<int> get sensitiveMarks;/// Fediverse/remote attachments often omit mime type; default safely.
 String get mimeType;/// Fediverse/remote attachments often omit content hash.
 String get hash; int get size; bool get hasCompression; bool get hasThumbnail;@JsonKey(name: "url", fromJson: _nonBlankUrl) String? get storageUrl; double? get width; double? get height;@JsonKey(name: 'blurhash') String? get blur; String? get usage; String? get applicationType;
/// Create a copy of SnCloudFileReference
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SnCloudFileReferenceCopyWith<SnCloudFileReference> get copyWith => _$SnCloudFileReferenceCopyWithImpl<SnCloudFileReference>(this as SnCloudFileReference, _$identity);

  /// Serializes this SnCloudFileReference to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SnCloudFileReference;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SnCloudFileReference&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&const DeepCollectionEquality().equals(other.fileMeta, _this.fileMeta)&&const DeepCollectionEquality().equals(other.userMeta, _this.userMeta)&&const DeepCollectionEquality().equals(other.sensitiveMarks, _this.sensitiveMarks)&&(identical(other.mimeType, _this.mimeType) || other.mimeType == _this.mimeType)&&(identical(other.hash, _this.hash) || other.hash == _this.hash)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.hasCompression, _this.hasCompression) || other.hasCompression == _this.hasCompression)&&(identical(other.hasThumbnail, _this.hasThumbnail) || other.hasThumbnail == _this.hasThumbnail)&&(identical(other.storageUrl, _this.storageUrl) || other.storageUrl == _this.storageUrl)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height)&&(identical(other.blur, _this.blur) || other.blur == _this.blur)&&(identical(other.usage, _this.usage) || other.usage == _this.usage)&&(identical(other.applicationType, _this.applicationType) || other.applicationType == _this.applicationType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SnCloudFileReference;
  return Object.hash(runtimeType,_this.id,_this.name,const DeepCollectionEquality().hash(_this.fileMeta),const DeepCollectionEquality().hash(_this.userMeta),const DeepCollectionEquality().hash(_this.sensitiveMarks),_this.mimeType,_this.hash,_this.size,_this.hasCompression,_this.hasThumbnail,_this.storageUrl,_this.width,_this.height,_this.blur,_this.usage,_this.applicationType);
}

@override
String toString() {
  final _this = this as SnCloudFileReference;
  return 'SnCloudFileReference(id: ${_this.id}, name: ${_this.name}, fileMeta: ${_this.fileMeta}, userMeta: ${_this.userMeta}, sensitiveMarks: ${_this.sensitiveMarks}, mimeType: ${_this.mimeType}, hash: ${_this.hash}, size: ${_this.size}, hasCompression: ${_this.hasCompression}, hasThumbnail: ${_this.hasThumbnail}, storageUrl: ${_this.storageUrl}, width: ${_this.width}, height: ${_this.height}, blur: ${_this.blur}, usage: ${_this.usage}, applicationType: ${_this.applicationType})';
}


}

/// @nodoc
abstract mixin class $SnCloudFileReferenceCopyWith<$Res>  {
  factory $SnCloudFileReferenceCopyWith(SnCloudFileReference value, $Res Function(SnCloudFileReference) _then) = _$SnCloudFileReferenceCopyWithImpl;
@useResult
$Res call({
 String id, String name, Map<String, dynamic> fileMeta, Map<String, dynamic> userMeta, List<int> sensitiveMarks, String mimeType, String hash, int size, bool hasCompression, bool hasThumbnail,@JsonKey(name: "url", fromJson: _nonBlankUrl) String? storageUrl, double? width, double? height,@JsonKey(name: 'blurhash') String? blur, String? usage, String? applicationType
});




}
/// @nodoc
class _$SnCloudFileReferenceCopyWithImpl<$Res>
    implements $SnCloudFileReferenceCopyWith<$Res> {
  _$SnCloudFileReferenceCopyWithImpl(this._self, this._then);

  final SnCloudFileReference _self;
  final $Res Function(SnCloudFileReference) _then;

/// Create a copy of SnCloudFileReference
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? fileMeta = null,Object? userMeta = null,Object? sensitiveMarks = null,Object? mimeType = null,Object? hash = null,Object? size = null,Object? hasCompression = null,Object? hasThumbnail = null,Object? storageUrl = freezed,Object? width = freezed,Object? height = freezed,Object? blur = freezed,Object? usage = freezed,Object? applicationType = freezed,}) {
  return _then(SnCloudFileReference(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,fileMeta: null == fileMeta ? _self.fileMeta : fileMeta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,userMeta: null == userMeta ? _self.userMeta : userMeta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,sensitiveMarks: null == sensitiveMarks ? _self.sensitiveMarks : sensitiveMarks // ignore: cast_nullable_to_non_nullable
as List<int>,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,hasCompression: null == hasCompression ? _self.hasCompression : hasCompression // ignore: cast_nullable_to_non_nullable
as bool,hasThumbnail: null == hasThumbnail ? _self.hasThumbnail : hasThumbnail // ignore: cast_nullable_to_non_nullable
as bool,storageUrl: freezed == storageUrl ? _self.storageUrl : storageUrl // ignore: cast_nullable_to_non_nullable
as String?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as double?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double?,blur: freezed == blur ? _self.blur : blur // ignore: cast_nullable_to_non_nullable
as String?,usage: freezed == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as String?,applicationType: freezed == applicationType ? _self.applicationType : applicationType // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SnCloudFileReference].
extension SnCloudFileReferencePatterns on SnCloudFileReference {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SnCloudFileReference value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SnCloudFileReference() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SnCloudFileReference value)  $default,){
final _that = this;
switch (_that) {
case _SnCloudFileReference():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SnCloudFileReference value)?  $default,){
final _that = this;
switch (_that) {
case _SnCloudFileReference() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  Map<String, dynamic> fileMeta,  Map<String, dynamic> userMeta,  List<int> sensitiveMarks,  String mimeType,  String hash,  int size,  bool hasCompression,  bool hasThumbnail, @JsonKey(name: "url", fromJson: _nonBlankUrl)  String? storageUrl,  double? width,  double? height, @JsonKey(name: 'blurhash')  String? blur,  String? usage,  String? applicationType)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SnCloudFileReference() when $default != null:
return $default(_that.id,_that.name,_that.fileMeta,_that.userMeta,_that.sensitiveMarks,_that.mimeType,_that.hash,_that.size,_that.hasCompression,_that.hasThumbnail,_that.storageUrl,_that.width,_that.height,_that.blur,_that.usage,_that.applicationType);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  Map<String, dynamic> fileMeta,  Map<String, dynamic> userMeta,  List<int> sensitiveMarks,  String mimeType,  String hash,  int size,  bool hasCompression,  bool hasThumbnail, @JsonKey(name: "url", fromJson: _nonBlankUrl)  String? storageUrl,  double? width,  double? height, @JsonKey(name: 'blurhash')  String? blur,  String? usage,  String? applicationType)  $default,) {final _that = this;
switch (_that) {
case _SnCloudFileReference():
return $default(_that.id,_that.name,_that.fileMeta,_that.userMeta,_that.sensitiveMarks,_that.mimeType,_that.hash,_that.size,_that.hasCompression,_that.hasThumbnail,_that.storageUrl,_that.width,_that.height,_that.blur,_that.usage,_that.applicationType);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  Map<String, dynamic> fileMeta,  Map<String, dynamic> userMeta,  List<int> sensitiveMarks,  String mimeType,  String hash,  int size,  bool hasCompression,  bool hasThumbnail, @JsonKey(name: "url", fromJson: _nonBlankUrl)  String? storageUrl,  double? width,  double? height, @JsonKey(name: 'blurhash')  String? blur,  String? usage,  String? applicationType)?  $default,) {final _that = this;
switch (_that) {
case _SnCloudFileReference() when $default != null:
return $default(_that.id,_that.name,_that.fileMeta,_that.userMeta,_that.sensitiveMarks,_that.mimeType,_that.hash,_that.size,_that.hasCompression,_that.hasThumbnail,_that.storageUrl,_that.width,_that.height,_that.blur,_that.usage,_that.applicationType);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SnCloudFileReference extends SnCloudFileReference {
  const _SnCloudFileReference({required this.id, this.name = '',  Map<String, dynamic> fileMeta = const {},  Map<String, dynamic> userMeta = const {},  List<int> sensitiveMarks = const [], this.mimeType = 'application/octet-stream', this.hash = '', this.size = 0, this.hasCompression = false, this.hasThumbnail = false, @JsonKey(name: "url", fromJson: _nonBlankUrl) this.storageUrl, this.width, this.height, @JsonKey(name: 'blurhash') this.blur, this.usage, this.applicationType}): _fileMeta = fileMeta,_userMeta = userMeta,_sensitiveMarks = sensitiveMarks,super._();
  factory _SnCloudFileReference.fromJson(Map<String, dynamic> json) => _$SnCloudFileReferenceFromJson(json);

@override final  String id;
@override@JsonKey() final  String name;
 final  Map<String, dynamic> _fileMeta;
@override@JsonKey() Map<String, dynamic> get fileMeta {
  if (_fileMeta is EqualUnmodifiableMapView) return _fileMeta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_fileMeta);
}

 final  Map<String, dynamic> _userMeta;
@override@JsonKey() Map<String, dynamic> get userMeta {
  if (_userMeta is EqualUnmodifiableMapView) return _userMeta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_userMeta);
}

 final  List<int> _sensitiveMarks;
@override@JsonKey() List<int> get sensitiveMarks {
  if (_sensitiveMarks is EqualUnmodifiableListView) return _sensitiveMarks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sensitiveMarks);
}

/// Fediverse/remote attachments often omit mime type; default safely.
@override@JsonKey() final  String mimeType;
/// Fediverse/remote attachments often omit content hash.
@override@JsonKey() final  String hash;
@override@JsonKey() final  int size;
@override@JsonKey() final  bool hasCompression;
@override@JsonKey() final  bool hasThumbnail;
@override@JsonKey(name: "url", fromJson: _nonBlankUrl) final  String? storageUrl;
@override final  double? width;
@override final  double? height;
@override@JsonKey(name: 'blurhash') final  String? blur;
@override final  String? usage;
@override final  String? applicationType;

/// Create a copy of SnCloudFileReference
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SnCloudFileReferenceCopyWith<_SnCloudFileReference> get copyWith => __$SnCloudFileReferenceCopyWithImpl<_SnCloudFileReference>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SnCloudFileReferenceToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SnCloudFileReference&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.fileMeta, _fileMeta)&&const DeepCollectionEquality().equals(other.userMeta, _userMeta)&&const DeepCollectionEquality().equals(other.sensitiveMarks, _sensitiveMarks)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.hash, hash) || other.hash == hash)&&(identical(other.size, size) || other.size == size)&&(identical(other.hasCompression, hasCompression) || other.hasCompression == hasCompression)&&(identical(other.hasThumbnail, hasThumbnail) || other.hasThumbnail == hasThumbnail)&&(identical(other.storageUrl, storageUrl) || other.storageUrl == storageUrl)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.blur, blur) || other.blur == blur)&&(identical(other.usage, usage) || other.usage == usage)&&(identical(other.applicationType, applicationType) || other.applicationType == applicationType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(_fileMeta),const DeepCollectionEquality().hash(_userMeta),const DeepCollectionEquality().hash(_sensitiveMarks),mimeType,hash,size,hasCompression,hasThumbnail,storageUrl,width,height,blur,usage,applicationType);
}

@override
String toString() {
    return 'SnCloudFileReference(id: $id, name: $name, fileMeta: $fileMeta, userMeta: $userMeta, sensitiveMarks: $sensitiveMarks, mimeType: $mimeType, hash: $hash, size: $size, hasCompression: $hasCompression, hasThumbnail: $hasThumbnail, storageUrl: $storageUrl, width: $width, height: $height, blur: $blur, usage: $usage, applicationType: $applicationType)';
}


}

/// @nodoc
abstract mixin class _$SnCloudFileReferenceCopyWith<$Res> implements $SnCloudFileReferenceCopyWith<$Res> {
  factory _$SnCloudFileReferenceCopyWith(_SnCloudFileReference value, $Res Function(_SnCloudFileReference) _then) = __$SnCloudFileReferenceCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, Map<String, dynamic> fileMeta, Map<String, dynamic> userMeta, List<int> sensitiveMarks, String mimeType, String hash, int size, bool hasCompression, bool hasThumbnail,@JsonKey(name: "url", fromJson: _nonBlankUrl) String? storageUrl, double? width, double? height,@JsonKey(name: 'blurhash') String? blur, String? usage, String? applicationType
});




}
/// @nodoc
class __$SnCloudFileReferenceCopyWithImpl<$Res>
    implements _$SnCloudFileReferenceCopyWith<$Res> {
  __$SnCloudFileReferenceCopyWithImpl(this._self, this._then);

  final _SnCloudFileReference _self;
  final $Res Function(_SnCloudFileReference) _then;

/// Create a copy of SnCloudFileReference
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? fileMeta = null,Object? userMeta = null,Object? sensitiveMarks = null,Object? mimeType = null,Object? hash = null,Object? size = null,Object? hasCompression = null,Object? hasThumbnail = null,Object? storageUrl = freezed,Object? width = freezed,Object? height = freezed,Object? blur = freezed,Object? usage = freezed,Object? applicationType = freezed,}) {
  return _then(_SnCloudFileReference(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,fileMeta: null == fileMeta ? _self._fileMeta : fileMeta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,userMeta: null == userMeta ? _self._userMeta : userMeta // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,sensitiveMarks: null == sensitiveMarks ? _self._sensitiveMarks : sensitiveMarks // ignore: cast_nullable_to_non_nullable
as List<int>,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,hash: null == hash ? _self.hash : hash // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,hasCompression: null == hasCompression ? _self.hasCompression : hasCompression // ignore: cast_nullable_to_non_nullable
as bool,hasThumbnail: null == hasThumbnail ? _self.hasThumbnail : hasThumbnail // ignore: cast_nullable_to_non_nullable
as bool,storageUrl: freezed == storageUrl ? _self.storageUrl : storageUrl // ignore: cast_nullable_to_non_nullable
as String?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as double?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double?,blur: freezed == blur ? _self.blur : blur // ignore: cast_nullable_to_non_nullable
as String?,usage: freezed == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as String?,applicationType: freezed == applicationType ? _self.applicationType : applicationType // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
