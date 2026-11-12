import 'dart:convert';
import 'package:http/http.dart' as http;

class StayingApiService {
  static const String baseUrl = 'https://api.stayingapi.com';

  // TEMPORARY: sandbox key for testing
  static const String apiKey = 'stay_test_upue6wcqzVaGCQRkL9bXVkKMZfuxqNaNLWulWlx4c48';

  Future<List<dynamic>> searchHotels({
    required String location,
    required String checkIn,
    required String checkOut,
    required int adults,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/v1/search'
          '?location=${Uri.encodeComponent(location)}'
          '&checkIn=$checkIn'
          '&checkOut=$checkOut'
          '&adults=$adults'
          '&platforms=google,booking'
          '&limit=20',
    );

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'StayingAPI search error '
            '${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body);

    return json['data'] ?? [];
  }

  // ==========================================================
  // GET HOTEL DETAILS + IMAGES
  // ==========================================================

Future<Map<String, dynamic>> getHotelDetails({
required String platform,
required String id,
String? country,
String? checkIn,
String? checkOut,
int adults = 2,
}) async {
final queryParameters = <String, String>{
'adults': adults.toString(),
};

if (country != null &&
country.isNotEmpty &&
platform == 'booking') {
queryParameters['country'] = country;
}

if (checkIn != null &&
checkIn.isNotEmpty) {
queryParameters['checkIn'] = checkIn;
}

if (checkOut != null &&
checkOut.isNotEmpty) {
queryParameters['checkOut'] = checkOut;
}

final uri = Uri.https(
'api.stayingapi.com',
'/v1/listing/$platform/$id',
queryParameters,
);

final response = await http.get(
uri,
headers: {
'Authorization':
'Bearer $apiKey',
'Accept':
'application/json',
},
);

if (response.statusCode != 200) {
throw Exception(
'StayingAPI listing error '
'${response.statusCode}: ${response.body}',
);
}

final json =
jsonDecode(response.body);

return Map<String, dynamic>.from(
json['data'] ?? {},
);
}}