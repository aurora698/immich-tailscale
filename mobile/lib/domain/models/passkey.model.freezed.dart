// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'passkey.model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Passkey {

 String get id; DateTime get createdAt; String? get name; DateTime? get usedAt;
/// Create a copy of Passkey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PasskeyCopyWith<Passkey> get copyWith => _$PasskeyCopyWithImpl<Passkey>(this as Passkey, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Passkey&&(identical(other.id, id) || other.id == id)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.name, name) || other.name == name)&&(identical(other.usedAt, usedAt) || other.usedAt == usedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,createdAt,name,usedAt);

@override
String toString() {
  return 'Passkey(id: $id, createdAt: $createdAt, name: $name, usedAt: $usedAt)';
}


}

/// @nodoc
abstract mixin class $PasskeyCopyWith<$Res>  {
  factory $PasskeyCopyWith(Passkey value, $Res Function(Passkey) _then) = _$PasskeyCopyWithImpl;
@useResult
$Res call({
 String id, DateTime createdAt, String? name, DateTime? usedAt
});




}
/// @nodoc
class _$PasskeyCopyWithImpl<$Res>
    implements $PasskeyCopyWith<$Res> {
  _$PasskeyCopyWithImpl(this._self, this._then);

  final Passkey _self;
  final $Res Function(Passkey) _then;

/// Create a copy of Passkey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? createdAt = null,Object? name = freezed,Object? usedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,usedAt: freezed == usedAt ? _self.usedAt : usedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Passkey].
extension PasskeyPatterns on Passkey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Passkey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Passkey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Passkey value)  $default,){
final _that = this;
switch (_that) {
case _Passkey():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Passkey value)?  $default,){
final _that = this;
switch (_that) {
case _Passkey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime createdAt,  String? name,  DateTime? usedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Passkey() when $default != null:
return $default(_that.id,_that.createdAt,_that.name,_that.usedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime createdAt,  String? name,  DateTime? usedAt)  $default,) {final _that = this;
switch (_that) {
case _Passkey():
return $default(_that.id,_that.createdAt,_that.name,_that.usedAt);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime createdAt,  String? name,  DateTime? usedAt)?  $default,) {final _that = this;
switch (_that) {
case _Passkey() when $default != null:
return $default(_that.id,_that.createdAt,_that.name,_that.usedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Passkey implements Passkey {
  const _Passkey({required this.id, required this.createdAt, this.name, this.usedAt});
  

@override final  String id;
@override final  DateTime createdAt;
@override final  String? name;
@override final  DateTime? usedAt;

/// Create a copy of Passkey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PasskeyCopyWith<_Passkey> get copyWith => __$PasskeyCopyWithImpl<_Passkey>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Passkey&&(identical(other.id, id) || other.id == id)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.name, name) || other.name == name)&&(identical(other.usedAt, usedAt) || other.usedAt == usedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,createdAt,name,usedAt);

@override
String toString() {
  return 'Passkey(id: $id, createdAt: $createdAt, name: $name, usedAt: $usedAt)';
}


}

/// @nodoc
abstract mixin class _$PasskeyCopyWith<$Res> implements $PasskeyCopyWith<$Res> {
  factory _$PasskeyCopyWith(_Passkey value, $Res Function(_Passkey) _then) = __$PasskeyCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime createdAt, String? name, DateTime? usedAt
});




}
/// @nodoc
class __$PasskeyCopyWithImpl<$Res>
    implements _$PasskeyCopyWith<$Res> {
  __$PasskeyCopyWithImpl(this._self, this._then);

  final _Passkey _self;
  final $Res Function(_Passkey) _then;

/// Create a copy of Passkey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? createdAt = null,Object? name = freezed,Object? usedAt = freezed,}) {
  return _then(_Passkey(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,usedAt: freezed == usedAt ? _self.usedAt : usedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
