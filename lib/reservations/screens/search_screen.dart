import 'package:flutter/material.dart';

import '../custom/app_colors.dart';
import '../custom/room_card.dart';
import '../services/staying_api_service.dart';
import '../services/reservation_service.dart';

import 'room_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _service = ReservationService.instance;

  late DateTime _checkIn;
  late DateTime _checkOut;

  int _guests = 2;

  // ==========================================================
  // STAYING API
  // ==========================================================

  bool _testingApi = false;

  String? _apiMessage;

  List<dynamic> _stayingHotels = [];

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _checkIn = DateTime(
      now.year,
      now.month,
      now.day,
    );

    _checkOut = _checkIn.add(
      const Duration(days: 3),
    );
  }

  // ==========================================================
  // PICK DATES
  // ==========================================================

  Future<void> _pickDates() async {
    final today = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,

      firstDate: DateTime(
        today.year,
        today.month,
        today.day,
      ),

      lastDate: today.add(
        const Duration(days: 365),
      ),

      initialDateRange: DateTimeRange(
        start: _checkIn,
        end: _checkOut,
      ),
    );

    if (picked != null) {
      setState(() {
        _checkIn = picked.start;
        _checkOut = picked.end;
      });
    }
  }

  // ==========================================================
  // STAYING API SEARCH
  // ==========================================================

  Future<void> _testStayingApi() async {
    setState(() {
      _testingApi = true;
      _apiMessage = null;
      _stayingHotels = [];
    });

    try {
      if (!await StayingApiService.isConfigured()) {
        if (!mounted) return;
        setState(() => _apiMessage =
            'La recherche externe n’est pas configurée sur cette version.');
        return;
      }
      final api = StayingApiService();

      // ========================================================
      // 1. SEARCH HOTELS
      // ========================================================

      final checkIn =
      _checkIn.toIso8601String().split('T')[0];

      final checkOut =
      _checkOut.toIso8601String().split('T')[0];

      final result = await api.searchHotels(
        location: 'Paris, France',

        checkIn: checkIn,

        checkOut: checkOut,

        adults: _guests,
      );

      debugPrint(
        '================ STAYING API SEARCH ================',
      );

      debugPrint(
        result.toString(),
      );

      debugPrint(
        '=====================================================',
      );

      // ========================================================
      // 2. GET FULL HOTEL DETAILS + IMAGES
      // ========================================================

      final List<dynamic> hotelsWithDetails = [];

      for (final hotel in result) {
        try {
          final platform =
          hotel['platform']?.toString();

          final platformListingId =
          hotel['platformListingId']?.toString();

          // Country is important for Booking.com
          String? country;

          if (hotel['location'] is Map) {
            country =
                hotel['location']['country']?.toString();
          }

          // If the search result doesn't contain
          // the required ID, keep the hotel anyway.
          if (platform == null ||
              platformListingId == null ||
              platform.isEmpty ||
              platformListingId.isEmpty) {
            debugPrint(
              'Hotel sans platformListingId : '
                  '${hotel['name']}',
            );

            hotelsWithDetails.add(hotel);

            continue;
          }

          debugPrint(
            'Getting hotel details: '
                '$platform / $platformListingId',
          );

          // Call the listing endpoint
          final details =
          await api.getHotelDetails(
            platform: platform,
            id: platformListingId,
            country: country,
            checkIn: checkIn,
            checkOut: checkOut,
            adults: _guests,
          );

          // Combine:
          // search result + full listing details
          final mergedHotel = <String, dynamic>{
            ...hotel,
            ...details,
          };

          hotelsWithDetails.add(
            mergedHotel,
          );

          debugPrint(
            'HOTEL: ${mergedHotel['name']}',
          );

          debugPrint(
            'PLATFORM: ${mergedHotel['platform']}',
          );

          debugPrint(
            'IMAGES: ${mergedHotel['images']}',
          );
        } catch (e) {
          // If the detail request fails,
          // we still keep the hotel returned
          // by the search endpoint.
          debugPrint(
            'DETAIL ERROR for '
                '${hotel['name']}: $e',
          );

          hotelsWithDetails.add(
            hotel,
          );
        }
      }

      debugPrint(
        '================ FINAL HOTELS ================',
      );

      debugPrint(
        hotelsWithDetails.toString(),
      );

      debugPrint(
        '================================================',
      );

      if (!mounted) return;

      setState(() {
        _stayingHotels =
            hotelsWithDetails;

        _apiMessage =
        '${hotelsWithDetails.length} hôtel(s) trouvé(s) avec StayingAPI ✅';
      });
    } catch (e) {
      debugPrint(
        'STAYING API ERROR: $e',
      );

      if (!mounted) return;

      setState(() {
        _apiMessage =
        'Erreur de recherche. Réessayez dans quelques instants.';

        _stayingHotels = [];
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _testingApi = false;
      });
    }
  }

  // ==========================================================
  // HOTEL IMAGE FALLBACK
  // ==========================================================

  Widget _hotelImageFallback() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.navy.withOpacity(0.08),
      ),
      child: const Center(
        child: Icon(
          Icons.hotel,
          size: 64,
          color: AppColors.navy,
        ),
      ),
    );
  }

  // ==========================================================
  // GET HOTEL IMAGE
  // ==========================================================

  String? _getHotelImage(dynamic hotel) {
    // ========================================================
    // IMAGE
    // ========================================================

    if (hotel['image'] != null) {
      final value =
      hotel['image'].toString();

      if (value.isNotEmpty) {
        return value;
      }
    }

    // ========================================================
    // IMAGE URL
    // ========================================================

    if (hotel['imageUrl'] != null) {
      final value =
      hotel['imageUrl'].toString();

      if (value.isNotEmpty) {
        return value;
      }
    }

    // ========================================================
    // PHOTO
    // ========================================================

    if (hotel['photo'] != null) {
      final value =
      hotel['photo'].toString();

      if (value.isNotEmpty) {
        return value;
      }
    }

    // ========================================================
    // PHOTO URL
    // ========================================================

    if (hotel['photoUrl'] != null) {
      final value =
      hotel['photoUrl'].toString();

      if (value.isNotEmpty) {
        return value;
      }
    }

    // ========================================================
    // IMAGES
    // ========================================================

    if (hotel['images'] is List) {
      final images =
      hotel['images'] as List;

      if (images.isNotEmpty) {
        final firstImage =
            images.first;

        // Example:
        // "images": [
        //   "https://example.com/photo.jpg"
        // ]

        if (firstImage is String) {
          if (firstImage.isNotEmpty) {
            return firstImage;
          }
        }

        // Example:
        // "images": [
        //   {
        //     "url":
        //       "https://example.com/photo.jpg"
        //   }
        // ]

        if (firstImage is Map) {
          if (firstImage['url'] != null) {
            final value =
            firstImage['url'].toString();

            if (value.isNotEmpty) {
              return value;
            }
          }

          if (firstImage['imageUrl'] != null) {
            final value =
            firstImage['imageUrl'].toString();

            if (value.isNotEmpty) {
              return value;
            }
          }

          if (firstImage['large'] != null) {
            final value =
            firstImage['large'].toString();

            if (value.isNotEmpty) {
              return value;
            }
          }
        }
      }
    }

    return null;
  }

  // ==========================================================
  // SHOW HOTEL DETAILS
  // ==========================================================

  void _showHotelDetails(dynamic hotel) {
    final String name =
        hotel['name']?.toString() ??
            'Hôtel sans nom';

    final String propertyType =
        hotel['propertyType']?.toString() ??
            'Hôtel';

    final dynamic starRating =
    hotel['starRating'];

    final dynamic guestRating =
    hotel['guestRating'];

    final dynamic reviewCount =
    hotel['reviewCount'];

    final dynamic amenities =
    hotel['amenities'];

    final String? imageUrl =
    _getHotelImage(hotel);

    String priceText =
        'Prix indisponible';

    final dynamic price =
    hotel['price'];

    if (price is Map) {
      final dynamic nightlyPrice =
      price['nightlyPrice'];

      final dynamic currency =
          price['currency'] ?? 'EUR';

      if (nightlyPrice != null) {
        priceText =
        '$nightlyPrice $currency / nuit';
      }
    } else if (price != null) {
      priceText =
      '${price.toString()} / nuit';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
      AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (
              context,
              scrollController,
              ) {
            return ListView(
              controller:
              scrollController,
              padding:
              const EdgeInsets.only(
                bottom: 30,
              ),
              children: [
                // ==================================================
                // IMAGE
                // ==================================================

                if (imageUrl != null &&
                    imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius:
                    const BorderRadius
                        .vertical(
                      top: Radius.circular(
                        28,
                      ),
                    ),
                    child: Image.network(
                      imageUrl,
                      height: 250,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (
                          context,
                          error,
                          stackTrace,
                          ) {
                        return _hotelImageFallback();
                      },
                    ),
                  )
                else
                  _hotelImageFallback(),

                // ==================================================
                // INFORMATION
                // ==================================================

                Padding(
                  padding:
                  const EdgeInsets.all(
                    20,
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        name,
                        style:
                        const TextStyle(
                          fontSize: 25,
                          fontWeight:
                          FontWeight.w700,
                          color:
                          AppColors.navy,
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      Text(
                        propertyType,
                        style:
                        const TextStyle(
                          color:
                          AppColors.muted,
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      // =================================================
                      // RATINGS
                      // =================================================

                      Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        children: [
                          if (starRating !=
                              null)
                            Row(
                              mainAxisSize:
                              MainAxisSize
                                  .min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  color:
                                  AppColors
                                      .gold,
                                ),
                                const SizedBox(
                                  width: 5,
                                ),
                                Text(
                                  '$starRating étoiles',
                                ),
                              ],
                            ),

                          if (guestRating !=
                              null)
                            Row(
                              mainAxisSize:
                              MainAxisSize
                                  .min,
                              children: [
                                const Icon(
                                  Icons
                                      .star_rate,
                                  color:
                                  AppColors
                                      .gold,
                                ),
                                const SizedBox(
                                  width: 5,
                                ),
                                Text(
                                  '$guestRating',
                                ),
                              ],
                            ),

                          if (reviewCount !=
                              null)
                            Text(
                              '($reviewCount avis)',
                              style:
                              const TextStyle(
                                color:
                                AppColors
                                    .muted,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(
                        height: 20,
                      ),

                      // =================================================
                      // PRICE
                      // =================================================

                      Text(
                        priceText,
                        style:
                        const TextStyle(
                          fontSize: 22,
                          fontWeight:
                          FontWeight.w700,
                          color:
                          AppColors.navy,
                        ),
                      ),

                      const SizedBox(
                        height: 20,
                      ),

                      // =================================================
                      // AMENITIES
                      // =================================================

                      if (amenities
                      is List &&
                          amenities.isNotEmpty) ...[
                        const Text(
                          'Équipements',
                          style:
                          TextStyle(
                            fontSize: 18,
                            fontWeight:
                            FontWeight.w700,
                            color:
                            AppColors.navy,
                          ),
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                          amenities
                              .map(
                                (item) =>
                                Chip(
                                  label:
                                  Text(
                                    item.toString(),
                                  ),
                                ),
                          )
                              .toList(),
                        ),
                      ],

                      const SizedBox(
                        height: 25,
                      ),

                      // =================================================
                      // CLOSE
                      // =================================================

                      SizedBox(
                        width:
                        double.infinity,
                        child:
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                            );
                          },
                          child:
                          const Text(
                            'Fermer',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // HOTEL CARD
  // ==========================================================

  Widget _buildStayingHotelCard(
      dynamic hotel) {
    final String name =
        hotel['name']?.toString() ??
            'Hôtel sans nom';

    final String propertyType =
        hotel['propertyType']?.toString() ??
            'Hôtel';

    final dynamic starRating =
    hotel['starRating'];

    final dynamic guestRating =
    hotel['guestRating'];

    final dynamic reviewCount =
    hotel['reviewCount'];

    final dynamic price =
    hotel['price'];

    final String? imageUrl =
    _getHotelImage(hotel);

    String priceText =
        'Prix indisponible';

    if (price is Map) {
      final dynamic nightlyPrice =
      price['nightlyPrice'];

      final dynamic currency =
          price['currency'] ?? 'EUR';

      if (nightlyPrice != null) {
        priceText =
        '$nightlyPrice $currency / nuit';
      }
    } else if (price != null) {
      priceText =
      '${price.toString()} / nuit';
    }

    return Card(
      margin: const EdgeInsets.only(
        bottom: 18,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(20),
      ),
      clipBehavior:
      Clip.antiAlias,

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          // ====================================================
          // IMAGE
          // ====================================================

          if (imageUrl != null &&
              imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,

              loadingBuilder: (
                  context,
                  child,
                  loadingProgress,
                  ) {
                if (loadingProgress ==
                    null) {
                  return child;
                }

                return Container(
                  height: 200,
                  width: double.infinity,
                  color: AppColors.navy
                      .withOpacity(0.08),
                  child: const Center(
                    child:
                    CircularProgressIndicator(),
                  ),
                );
              },

              errorBuilder: (
                  context,
                  error,
                  stackTrace,
                  ) {
                return _hotelImageFallback();
              },
            )
          else
            _hotelImageFallback(),

          // ====================================================
          // INFORMATION
          // ====================================================

          Padding(
            padding:
            const EdgeInsets.all(16),

            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                // NAME

                Text(
                  name,
                  style:
                  const TextStyle(
                    fontSize: 20,
                    fontWeight:
                    FontWeight.w700,
                    color:
                    AppColors.navy,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                // TYPE

                Text(
                  propertyType,
                  style:
                  const TextStyle(
                    color:
                    AppColors.muted,
                  ),
                ),

                const SizedBox(
                  height: 10,
                ),

                // =================================================
                // RATINGS
                // =================================================

                Row(
                  children: [
                    if (starRating !=
                        null) ...[
                      const Icon(
                        Icons.star,
                        size: 18,
                        color:
                        AppColors.gold,
                      ),

                      const SizedBox(
                        width: 4,
                      ),

                      Text(
                        '$starRating étoiles',
                      ),
                    ],

                    if (guestRating !=
                        null) ...[
                      const SizedBox(
                        width: 14,
                      ),

                      const Icon(
                        Icons.star_rate,
                        size: 18,
                        color:
                        AppColors.gold,
                      ),

                      const SizedBox(
                        width: 4,
                      ),

                      Text(
                        '$guestRating',
                      ),
                    ],

                    if (reviewCount !=
                        null) ...[
                      const SizedBox(
                        width: 5,
                      ),

                      Text(
                        '($reviewCount avis)',
                        style:
                        const TextStyle(
                          color:
                          AppColors
                              .muted,
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(
                  height: 12,
                ),

                // =================================================
                // PRICE
                // =================================================

                Text(
                  priceText,
                  style:
                  const TextStyle(
                    fontSize: 18,
                    fontWeight:
                    FontWeight.w700,
                    color:
                    AppColors.navy,
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                // =================================================
                // BUTTON
                // =================================================

                SizedBox(
                  width:
                  double.infinity,
                  child:
                  ElevatedButton(
                    onPressed: () {
                      _showHotelDetails(
                        hotel,
                      );
                    },

                    child:
                    const Text(
                      'Voir l’hôtel',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
      BuildContext context) {
    return Scaffold(
      backgroundColor:
      AppColors.background,

      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        title:
        const Text('Nova Paris'),
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: ListenableBuilder(
        listenable: _service,

        builder: (
            context,
            _,
            ) {
          // ====================================================
          // LOCAL ROOMS
          // ====================================================

          final rooms =
          _service.availableRooms(
            _checkIn,
            _checkOut,
            _guests,
          );

          return ListView(
            padding:
            const EdgeInsets.all(20),

            children: [
              // ==================================================
              // TITLE
              // ==================================================

              const Text(
                'Trouvez votre\nchambre idéale.',
                style:
                TextStyle(
                  fontSize: 28,
                  color:
                  AppColors.navy,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // ==================================================
              // SEARCH CARD
              // ==================================================

              Card(
                elevation: 0,

                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    20,
                  ),
                ),

                child: Padding(
                  padding:
                  const EdgeInsets.all(
                    16,
                  ),

                  child: Column(
                    children: [
                      // ==========================================
                      // DATES
                      // ==========================================

                      ListTile(
                        contentPadding:
                        EdgeInsets.zero,

                        leading:
                        const Icon(
                          Icons
                              .calendar_today,
                          color:
                          AppColors.navy,
                        ),

                        title:
                        Text(
                          '${fmtDate(_checkIn)}  →  ${fmtDate(_checkOut)}',
                        ),

                        subtitle:
                        Text(
                          '${_checkOut.difference(_checkIn).inDays} nuit(s)',
                        ),

                        onTap:
                        _pickDates,
                      ),

                      // ==========================================
                      // GUESTS
                      // ==========================================

                      Row(
                        children: [
                          const Icon(
                            Icons
                                .people_outline,
                            color:
                            AppColors.navy,
                          ),

                          const SizedBox(
                            width: 16,
                          ),

                          const Expanded(
                            child:
                            Text(
                              'Voyageurs',
                            ),
                          ),

                          IconButton(
                            onPressed:
                            _guests >
                                1
                                ? () {
                              setState(
                                    () {
                                  _guests--;
                                },
                              );
                            }
                                : null,

                            icon:
                            const Icon(
                              Icons
                                  .remove_circle_outline,
                            ),
                          ),

                          Text(
                            '$_guests',

                            style:
                            const TextStyle(
                              fontSize:
                              16,
                            ),
                          ),

                          IconButton(
                            onPressed:
                            _guests <
                                6
                                ? () {
                              setState(
                                    () {
                                  _guests++;
                                },
                              );
                            }
                                : null,

                            icon:
                            const Icon(
                              Icons
                                  .add_circle_outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // ==================================================
              // STAYING API BUTTON
              // ==================================================

              SizedBox(
                width:
                double.infinity,

                child:
                ElevatedButton.icon(
                  onPressed:
                  _testingApi
                      ? null
                      : _testStayingApi,

                  icon:
                  _testingApi
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth:
                      2,
                    ),
                  )
                      : const Icon(
                    Icons
                        .cloud_outlined,
                  ),

                  label:
                  Text(
                    _testingApi
                        ? 'Recherche en cours...'
                        : 'Rechercher des hôtels',
                  ),
                ),
              ),

              // ==================================================
              // API MESSAGE
              // ==================================================

              if (_apiMessage !=
                  null) ...[
                const SizedBox(
                  height: 12,
                ),

                Container(
                  width:
                  double.infinity,

                  padding:
                  const EdgeInsets.all(
                    14,
                  ),

                  decoration:
                  BoxDecoration(
                    color:
                    _apiMessage!
                        .contains(
                        'trouvé')
                        ? Colors
                        .green
                        .withOpacity(
                      0.1,
                    )
                        : Colors
                        .red
                        .withOpacity(
                      0.1,
                    ),

                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                  ),

                  child:
                  Text(
                    _apiMessage!,

                    style:
                    TextStyle(
                      color: _apiMessage!
                          .contains(
                          'trouvé')
                          ? Colors
                          .green
                          .shade800
                          : Colors
                          .red
                          .shade800,
                    ),
                  ),
                ),
              ],

              const SizedBox(
                height: 24,
              ),

              // ==================================================
              // LOCAL ROOMS
              // ==================================================

              Text(
                '${rooms.length} chambre(s) disponible(s)',

                style:
                const TextStyle(
                  fontWeight:
                  FontWeight.w600,
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              // ==================================================
              // NO LOCAL ROOMS
              // ==================================================

              if (rooms.isEmpty)
                const Padding(
                  padding:
                  EdgeInsets.all(24),

                  child: Center(
                    child:
                    Text(
                      'Aucune chambre disponible pour ces dates.',

                      style:
                      TextStyle(
                        color:
                        AppColors
                            .muted,
                      ),
                    ),
                  ),
                ),

              // ==================================================
              // YOUR EXISTING LOCAL ROOMS
              // ==================================================

              ...rooms.map(
                    (room) =>
                    RoomCard(
                      room: room,

                      onTap: () {
                        Navigator.push(
                          context,

                          MaterialPageRoute(
                            builder:
                                (_) =>
                                RoomDetailScreen(
                                  room:
                                  room,

                                  checkIn:
                                  _checkIn,

                                  checkOut:
                                  _checkOut,

                                  guests:
                                  _guests,
                                ),
                          ),
                        );
                      },
                    ),
              ),

              // ==================================================
              // STAYING API HOTELS
              // ==================================================

              if (_stayingHotels
                  .isNotEmpty) ...[
                const SizedBox(
                  height: 30,
                ),

                const Text(
                  'Hôtels disponibles',

                  style:
                  TextStyle(
                    fontSize: 22,
                    fontWeight:
                    FontWeight.w700,
                    color:
                    AppColors.navy,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                Text(
                  '${_stayingHotels.length} hôtel(s) trouvé(s) avec StayingAPI',

                  style:
                  const TextStyle(
                    color:
                    AppColors.muted,
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                // SHOW ALL API RESULTS

                ..._stayingHotels.map(
                      (hotel) =>
                      _buildStayingHotelCard(
                        hotel,
                      ),
                ),
              ],

              const SizedBox(
                height: 20,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==========================================================
// DATE FORMAT
// ==========================================================

String fmtDate(
    DateTime date) {
  final day =
  date.day.toString().padLeft(
    2,
    '0',
  );

  final month =
  date.month.toString().padLeft(
    2,
    '0',
  );

  return '$day/$month/${date.year}';
}
