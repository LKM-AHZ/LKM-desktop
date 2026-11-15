import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart'
    as pi;

const _channel = MethodChannel('flutter.baseflow.com/geocoding');

class GeocodingOhos extends pi.GeocodingPlatformFactory {
  static void registerWith() =>
      pi.GeocodingPlatformFactory.instance = GeocodingOhos();
  @override
  pi.Geocoding createGeocoding(pi.GeocodingCreationParams params) =>
      _GeocodingOhos(params);
}

class _GeocodingOhos extends pi.Geocoding {
  _GeocodingOhos(super.params) : super.implementation();
  Future<List<Map<Object?, Object?>>> _query(
    String method,
    Map<String, Object?> args,
    Locale? locale,
  ) async {
    final rows = await _channel.invokeListMethod<Object?>(method, {
      ...args,
      if (locale != null) 'localeIdentifier': locale.toLanguageTag(),
    });
    return (rows ?? [])
        .map((row) => Map<Object?, Object?>.from(row as Map))
        .toList();
  }

  @override
  Future<bool> isPresent() async =>
      await _channel.invokeMethod<bool>('isPresent') ?? false;
  @override
  Future<List<pi.Location>> locationFromAddress(
    String address, {
    Locale? locale,
  }) async =>
      (await _query('locationFromAddress', {'address': address}, locale))
          .map(
            (row) => pi.Location(
              latitude: (row['latitude'] as num).toDouble(),
              longitude: (row['longitude'] as num).toDouble(),
            ),
          )
          .toList();
  @override
  Future<List<pi.Placemark>> placemarkFromAddress(
    String address, {
    Locale? locale,
  }) async => (await _query('placemarkFromAddress', {
    'address': address,
  }, locale)).map(_placemark).toList();
  @override
  Future<List<pi.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    Locale? locale,
  }) async => (await _query('placemarkFromCoordinates', {
    'latitude': latitude,
    'longitude': longitude,
  }, locale)).map(_placemark).toList();
  pi.Placemark _placemark(Map<Object?, Object?> row) => pi.Placemark(
    name: row['name'] as String?,
    street: row['street'] as String?,
    isoCountryCode: row['isoCountryCode'] as String?,
    country: row['country'] as String?,
    postalCode: row['postalCode'] as String?,
    administrativeArea: row['administrativeArea'] as String?,
    subAdministrativeArea: row['subAdministrativeArea'] as String?,
    locality: row['locality'] as String?,
    subLocality: row['subLocality'] as String?,
    thoroughfare: row['thoroughfare'] as String?,
    subThoroughfare: row['subThoroughfare'] as String?,
  );
}
