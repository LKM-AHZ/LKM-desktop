# geocoding_ohos 1.0.0, current API forward port

Source: https://gitcode.com/CPF-Flutter/fluttertpc_geocoding
Fixed commit: 258b4af80fd58f0ba94d7fc3ffdd22af3097fb99
Path: geocoding_ohos. Original LICENSE retained; native Apache LICENSE-OHOS
included in Flutter notices, Huawei native header retained.

Forward port to current geocoding_platform_interface 5.0.0 factory/instance API.
Native LocationKit uses request-local BCP47 locale instead of a shared mutable
locale; never treats locale country as a search-region restriction. Standard
codec arrays/maps, real optional coordinates, no fabricated timestamp/0,0.
Dart converts numeric coordinates to doubles. SDK sync/async errors and engine
detach settle pending results once; absent placemark fields stay absent.
Existing geocoding 5.0.1 source/other platforms unchanged. The shared weather
lookup now permits OHOS and preserves its existing coordinate fallback.

SDK service availability, network/region coverage and real geocoder responses
need device verification. This service converts supplied addresses/coordinates;
it does not access the device location or bypass geolocator permission handling.
