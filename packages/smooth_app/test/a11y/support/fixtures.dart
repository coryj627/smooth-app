/// The data behind the audited screens: products, and the answers of the
/// Open Food Facts servers.
///
/// The complete product is the app's own `assets/onboarding/
/// sample_product_data.json`: a real server response with attribute groups
/// and all its knowledge panels.  The others are that response with the
/// fields a shopper would see changed, or cut down.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:openfoodfacts/openfoodfacts.dart';

import 'fake_backend.dart';

const String kUserId = 'a11y-tester';
const String kPassword = 'correct-horse';

/// The complete product (the app's onboarding sample).
const String kComplete = '93270067481501';

/// A product someone added with a name and nothing else.
const String kSparse = '8901234567890';

/// A barcode the server does not know.
const String kUnknown = '4006381333931';

/// Further complete products, for lists.
const String kHazelnutSpread = '3017620422003';
const String kOatDrink = '7394376616228';
const String kCola = '5449000000996';
const String kMuesli = '4000521006549';

const List<String> kListBarcodes = <String>[
  kComplete,
  kHazelnutSpread,
  kOatDrink,
  kCola,
  kMuesli,
];

final Map<String, Object?> _sample = jsonDecode(
  File('assets/onboarding/sample_product_data.json').readAsStringSync(),
) as Map<String, Object?>;

Map<String, Object?> _copy(Object? json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

/// Sets the score a list row and the product header show.
void _setAttribute(
  Map<String, Object?> product,
  String id, {
  required String title,
  required double match,
  required String icon,
  String? description,
}) {
  for (final Object? group in product['attribute_groups']! as List<Object?>) {
    for (final Object? attribute
        in (group! as Map<String, Object?>)['attributes']! as List<Object?>) {
      final Map<String, Object?> map = attribute! as Map<String, Object?>;
      if (map['id'] == id) {
        map['title'] = title;
        map['match'] = match;
        map['icon_url'] =
            'https://static.openfoodfacts.org/images/attributes/dist/$icon.svg';
        if (description != null) {
          map['description_short'] = description;
        }
      }
    }
  }
}

Map<String, Object?> _variant(
  String barcode, {
  required String name,
  required String brands,
  required String quantity,
  required String nutriscore,
  required int nova,
  required String greenScore,
}) {
  final Map<String, Object?> product = _copy(_sample['product']);
  product['code'] = barcode;
  product['product_name'] = name;
  product['brands'] = brands;
  product['quantity'] = quantity;
  product['nutrition_grade_fr'] = nutriscore;
  product['nutriscore_grade'] = nutriscore;
  product['nova_group'] = nova;
  product['ecoscore_grade'] = greenScore;
  product['brands_tags'] = <String>[brands.toLowerCase()];
  const Map<String, double> match = <String, double>{
    'a': 100,
    'b': 80,
    'c': 60,
    'd': 30,
    'e': 0,
  };
  _setAttribute(
    product,
    'nutriscore',
    title: 'Nutri-Score ${nutriscore.toUpperCase()}',
    match: match[nutriscore]!,
    icon: 'nutriscore-$nutriscore-new-en',
  );
  _setAttribute(
    product,
    'nova',
    title: const <int, String>{
      1: 'Unprocessed or minimally processed foods',
      2: 'Processed culinary ingredients',
      3: 'Processed foods',
      4: 'Ultra processed foods',
    }[nova]!,
    match: const <int, double>{1: 100, 2: 100, 3: 75, 4: 0}[nova]!,
    icon: 'nova-group-$nova',
  );
  _setAttribute(
    product,
    'ecoscore',
    title: 'Green-Score ${greenScore.toUpperCase()}',
    match: match[greenScore]!,
    icon: 'green-score-$greenScore',
  );
  return _upToDate(product);
}

/// Adds the fields the app asks the server for today that the shipped sample
/// (an older, narrower query) does not have.
Map<String, Object?> _upToDate(Map<String, Object?> product) {
  final String name = product['product_name']! as String;
  Map<String, Object?> sizes(int side) => <String, Object?>{
    'sizes': <String, Object?>{
      '100': <String, Object?>{'w': 100, 'h': 100},
      '200': <String, Object?>{'w': 200, 'h': 200},
      '400': <String, Object?>{'w': 400, 'h': 400},
      'full': <String, Object?>{'w': side, 'h': side},
    },
  };
  // The server now also sends "simplified" cards, which the product page
  // builds its Health and Environment tabs from.  The shipped sample predates
  // them, so they are put together here from the sample's own panels, in the
  // shape the app's test/knowledge_panel/simplified_health_card_test.dart
  // describes ("the panels the server sends for a food product").
  final Map<String, Object?> panels =
      product['knowledge_panels']! as Map<String, Object?>;
  Map<String, Object?> group(List<String> ids) => <String, Object?>{
    'element_type': 'panel_group',
    'panel_group_element': <String, Object?>{'panel_ids': ids},
  };
  Map<String, Object?> panel(String id) => <String, Object?>{
    'element_type': 'panel',
    'panel_element': <String, Object?>{'panel_id': id},
  };
  Map<String, Object?> card(String from, List<Object?> elements) =>
      <String, Object?>{
        ...panels[from]! as Map<String, Object?>,
        'elements': elements,
      };
  panels['health_card_simplified'] = card('health_card', <Object?>[
    group(<String>['nutriscore_2023', 'nutrient_levels']),
    group(<String>['nova', 'additives']),
  ]);
  panels['environment_card_simplified'] = card('environment_card', <Object?>[
    group(<String>['environmental_score']),
  ]);
  panels['simplified_root'] = <String, Object?>{
    'type': 'root',
    'expanded': true,
    'elements': <Object?>[
      panel('health_card_simplified'),
      panel('environment_card_simplified'),
    ],
  };
  return <String, Object?>{
    ...product,
    'product_type': 'food',
    'product_name_languages': <String, Object?>{'en': name},
    'ingredients_text':
        (product['ingredients_text_languages']! as Map<String, Object?>)['en'],
    'categories_tags': <String>[
      'en:plant-based-foods-and-beverages',
      'en:plant-based-foods',
      'en:fruits-and-vegetables-based-foods',
      'en:meals',
      'en:soups',
      'en:vegetable-soups',
    ],
    'countries': 'United States, France',
    'countries_tags': <String>['en:united-states', 'en:france'],
    'countries_tags_en': <String>['United States', 'France'],
    'stores': 'Whole Foods, Carrefour',
    'origins': 'France',
    'emb_codes': 'FR 29.021.001 EC',
    'link': 'https://world.openfoodfacts.org',
    'last_modified_t': 1762300800,
    'packaging': 'Glass bottle, Steel cap',
    'packaging_tags': <String>['en:glass-bottle', 'en:steel-cap'],
    'packagings_complete': 1,
    'packagings': <Object?>[
      <String, Object?>{
        'number_of_units': 1,
        'shape': <String, Object?>{'id': 'en:bottle', 'lc_name': 'Bottle'},
        'material': <String, Object?>{'id': 'en:glass', 'lc_name': 'Glass'},
        'recycling': <String, Object?>{
          'id': 'en:recycle',
          'lc_name': 'Recycle',
        },
        'weight_measured': 300,
        'quantity_per_unit': '200 g',
      },
      <String, Object?>{
        'number_of_units': 1,
        'shape': <String, Object?>{
          'id': 'en:bottle-cap',
          'lc_name': 'Bottle cap',
        },
        'material': <String, Object?>{'id': 'en:steel', 'lc_name': 'Steel'},
        'weight_measured': 3,
      },
    ],
    'images': <String, Object?>{
      for (final String id in <String>['1', '2', '3', '4'])
        id: <String, Object?>{
          ...sizes(1200),
          'uploaded_t': 1731000000,
          'uploader': 'openfoodfacts-contributors',
        },
      'front_en': <String, Object?>{
        ...sizes(1200),
        'imgid': '1',
        'rev': '2607',
      },
      'ingredients_en': <String, Object?>{
        ...sizes(1200),
        'imgid': '2',
        'rev': '2613',
      },
      'nutrition_en': <String, Object?>{
        ...sizes(1200),
        'imgid': '3',
        'rev': '2618',
      },
    },
  };
}

final Map<String, Map<String, Object?>>
_products = <String, Map<String, Object?>>{
  kComplete: _upToDate(_copy(_sample['product'])),
  kHazelnutSpread: _variant(
    kHazelnutSpread,
    name: 'Hazelnut spread with cocoa',
    brands: 'Ferrero, Nutella',
    quantity: '400 g',
    nutriscore: 'e',
    nova: 4,
    greenScore: 'd',
  ),
  kOatDrink: _variant(
    kOatDrink,
    name: 'Oat drink barista edition',
    brands: 'Oatly',
    quantity: '1 l',
    nutriscore: 'b',
    nova: 3,
    greenScore: 'a',
  ),
  kCola: _variant(
    kCola,
    name: 'Coca-Cola Original Taste',
    brands: 'Coca-Cola',
    quantity: '330 ml',
    nutriscore: 'e',
    nova: 4,
    greenScore: 'c',
  ),
  kMuesli: _variant(
    kMuesli,
    name: 'Crunchy muesli with red berries and dark chocolate, no added sugar',
    brands: 'Kölln',
    quantity: '500 g',
    nutriscore: 'a',
    nova: 3,
    greenScore: 'b',
  ),
  // One photo and a name: the least the app shows as a product (with no
  // photo at all it offers to create the product instead).
  kSparse: <String, Object?>{
    'code': kSparse,
    'product_name': 'Chili crisp',
    'product_name_languages': <String, Object?>{'en': 'Chili crisp'},
    'product_type': 'food',
    'lang': 'en',
    'last_modified_t': 1762300800,
    'images': <String, Object?>{
      '1': <String, Object?>{
        'sizes': <String, Object?>{
          '100': <String, Object?>{'w': 100, 'h': 100},
          '400': <String, Object?>{'w': 400, 'h': 400},
          'full': <String, Object?>{'w': 1200, 'h': 1200},
        },
        'uploaded_t': 1762300800,
        'uploader': 'a11y-tester',
      },
      'front_en': <String, Object?>{
        'sizes': <String, Object?>{
          '100': <String, Object?>{'w': 100, 'h': 100},
          '200': <String, Object?>{'w': 200, 'h': 200},
          '400': <String, Object?>{'w': 400, 'h': 400},
          'full': <String, Object?>{'w': 1200, 'h': 1200},
        },
        'imgid': '1',
        'rev': '3',
      },
    },
    'states_tags': <String>[
      'en:to-be-completed',
      'en:nutrition-facts-to-be-completed',
      'en:ingredients-to-be-completed',
      'en:expiration-date-to-be-completed',
      'en:packaging-code-to-be-completed',
      'en:characteristics-to-be-completed',
      'en:origins-to-be-completed',
      'en:categories-to-be-completed',
      'en:brands-to-be-completed',
      'en:packaging-to-be-completed',
      'en:quantity-to-be-completed',
      'en:product-name-completed',
      'en:photos-to-be-validated',
      'en:front-photo-selected',
      'en:photos-uploaded',
    ],
  },
};

/// The server's JSON for [barcode].
Map<String, Object?> productJson(String barcode) => _copy(_products[barcode]);

/// The product as the app stores it once downloaded: parsed and
/// post-processed as `OpenFoodAPIClient.getProductV3` does.
Product product(String barcode) {
  final Product result = Product.fromJson(productJson(barcode));
  ProductHelper.removeImages(result, OpenFoodFactsLanguage.ENGLISH);
  ProductHelper.createImageUrls(result, uriHelper: uriHelperFoodProd);
  return result;
}

/// The routes every test starts with.
List<Answer> defaultRoutes() => <Answer>[
  // GET /api/v3.x/product/<barcode>
  (http.Request request) {
    final List<String> segments = request.url.pathSegments
        .where((String s) => s.isNotEmpty)
        .toList();
    if (request.method != 'GET' ||
        segments.length != 4 ||
        segments[0] != 'api' ||
        segments[2] != 'product') {
      return null;
    }
    // "example" is the product of the onboarding.
    final String barcode = segments[3] == 'example'
        ? kComplete
        : segments[3].replaceAll('.json', '');
    if (!_products.containsKey(barcode)) {
      return FakeServers.json(<String, Object?>{
        'code': barcode,
        'status': 'failure',
        'result': <String, Object?>{
          'id': 'product_not_found',
          'name': 'Product not found',
          'lc_name': 'Product not found',
        },
        'errors': <Object?>[],
        'warnings': <Object?>[],
      }, status: 404);
    }
    return FakeServers.json(<String, Object?>{
      'code': barcode,
      'product': productJson(barcode),
      'status': 'success',
      'result': <String, Object?>{
        'id': 'product_found',
        'name': 'Product found',
        'lc_name': 'Product found',
      },
      'errors': <Object?>[],
      'warnings': <Object?>[],
    });
  },
  // The reference data the app refreshes at start: the same files it ships.
  (http.Request request) => switch (request.url.path) {
    '/api/v3.4/preferences' => http.Response(
      File('assets/metadata/init_preferences_en.json').readAsStringSync(),
      200,
      headers: _json,
    ),
    '/api/v3.4/attribute_groups' => http.Response(
      File('assets/metadata/init_attribute_groups_en.json').readAsStringSync(),
      200,
      headers: _json,
    ),
    _ => null,
  },
  // Score and label pictograms: the copies the app ships, else a grey box.
  (http.Request request) {
    if (!request.url.path.endsWith('.svg')) {
      return null;
    }
    final String name = request.url.pathSegments.last;
    for (final String dir in <String>['assets/cache', 'assets/cacheTintable']) {
      final File cached = File('$dir/$name');
      if (cached.existsSync()) {
        return http.Response.bytes(
          cached.readAsBytesSync(),
          200,
          headers: _svg,
        );
      }
    }
    standInSvgs.add(name);
    return http.Response(_greySvg, 200, headers: _svg);
  },
  // Map tiles (flutter_map): one drawn tile, the same everywhere.
  (http.Request request) => request.url.host == 'tile.openstreetmap.org'
      ? http.Response.bytes(
          File('test/a11y/support/map_tile.png').readAsBytesSync(),
          200,
          headers: <String, String>{'content-type': 'image/png'},
        )
      : null,
  _auth,
  // Saving a product (the app sends edits in the background).
  (http.Request request) => request.url.path == '/cgi/product_jqm2.pl'
      ? FakeServers.json(<String, Object?>{
          'status': 1,
          'status_verbose': 'fields saved',
        })
      : null,
  _nutrients,
  _suggestions,
  _search,
  _prices,
  _folksonomy,
  _robotoff,
  _photo,
];

const Map<String, Object?> _store = <String, Object?>{
  'id': 4107,
  'type': 'OSM',
  'osm_id': 2305251225,
  'osm_type': 'NODE',
  'osm_name': 'Whole Foods Market',
  'osm_display_name': 'Whole Foods Market, 95, East Houston Street, Manhattan, New York, 10002, United States',
  'osm_address_postcode': '10002',
  'osm_address_city': 'New York',
  'osm_address_country': 'United States',
  'osm_address_country_code': 'US',
  'osm_tag_key': 'shop',
  'osm_tag_value': 'supermarket',
  'osm_lat': 40.7236,
  'osm_lon': -73.9921,
  'price_count': 312,
  'user_count': 9,
  'product_count': 270,
  'proof_count': 41,
  'created': '2025-03-02T10:21:07.000000Z',
  'updated': '2026-10-30T17:02:44.000000Z',
};

Map<String, Object?> _price(
  int id,
  String barcode, {
  required num amount,
  required String date,
  required String owner,
  num? withoutDiscount,
}) => <String, Object?>{
  'id': id,
  'type': 'PRODUCT',
  'product_code': barcode,
  'product_name': null,
  'category_tag': null,
  'labels_tags': null,
  'origins_tags': null,
  'price': amount,
  'price_is_discounted': withoutDiscount != null,
  'price_without_discount': withoutDiscount,
  'discount_type': withoutDiscount == null ? null : 'SALE',
  'price_per': null,
  'currency': 'USD',
  'location_osm_id': 2305251225,
  'location_osm_type': 'NODE',
  'location_id': 4107,
  'date': date,
  'proof_id': 9000 + id,
  'product_id': 77123,
  'receipt_quantity': 1,
  'owner': owner,
  'created': '${date}T18:30:00.000000Z',
  'updated': null,
  'location': _store,
  'proof': <String, Object?>{
    'id': 9000 + id,
    'file_path': '/0009/proof$id.webp',
    'image_thumb_path': '/0009/proof$id.400.webp',
    'mimetype': 'image/webp',
    'type': 'PRICE_TAG',
    'price_count': 3,
    'location_osm_id': 2305251225,
    'location_osm_type': 'NODE',
    'location_id': 4107,
    'date': date,
    'currency': 'USD',
    'owner': owner,
    'created': '${date}T18:29:00.000000Z',
    'updated': null,
  },
  'product': <String, Object?>{
    'id': 77123,
    'code': barcode,
    'price_count': 3,
    'location_count': 1,
    'user_count': 2,
    'proof_count': 3,
    'source': 'off',
    'product_name': _products[barcode]?['product_name'],
    'product_quantity': 200,
    'product_quantity_unit': 'g',
    'categories_tags': <String>['en:soups'],
    'brands': _products[barcode]?['brands'],
    'brands_tags': <String>[],
    'labels_tags': <String>['en:organic'],
    'image_url': 'https://images.openfoodfacts.org/images/products/932/700/674/81501/front_en.2607.400.jpg',
    'nutriscore_grade': 'a',
    'ecoscore_grade': 'a-plus',
    'nova_group': 3,
    'unique_scans_n': 120,
    'created': '2025-03-02T10:21:07.000000Z',
    'updated': '2026-10-30T17:02:44.000000Z',
  },
};

/// POST /cgi/auth.pl: one account, [kUserId] with [kPassword].
http.Response? _auth(http.Request request) {
  if (request.url.path != '/cgi/auth.pl') {
    return null;
  }
  final Map<String, String> fields = request.bodyFields;
  if (fields['user_id'] == kUserId && fields['password'] == kPassword) {
    return http.Response(
      jsonEncode(<String, Object?>{
        'status': 1,
        'status_verbose': 'user signed-in',
        'user_id': kUserId,
        'user': <String, Object?>{
          'email': 'a11y-tester@example.org',
          'name': 'Alex Tester',
          'preferred_language': 'en',
          'cc': 'us',
          'moderator': 0,
          'admin': 0,
        },
      }),
      200,
      headers: <String, String>{..._json, 'set-cookie': 'session=a11y'},
    );
  }
  return FakeServers.json(<String, Object?>{
    'status': 0,
    'status_verbose': 'user not signed-in',
    'user': <String, Object?>{},
  }, status: 403);
}

/// POST /cgi/nutrients.pl: the nutrients of the nutrition facts editor, in
/// the order of a nutrition label.  Written for this harness (the app ships
/// no copy): the usual label lines, with the server's nutrient ids.
http.Response? _nutrients(http.Request request) {
  if (request.url.path != '/cgi/nutrients.pl') {
    return null;
  }
  Map<String, Object?> nutrient(
    String id,
    String name, {
    bool important = true,
    String unit = 'g',
    List<Object?> sub = const <Object?>[],
  }) => <String, Object?>{
    'id': id,
    'name': name,
    'important': important,
    'display_in_edit_form': important,
    'unit': unit,
    if (sub.isNotEmpty) 'nutrients': sub,
  };
  return FakeServers.json(<String, Object?>{
    'nutrients': <Object?>[
      nutrient('energy-kj', 'Energy (kJ)', unit: 'kJ'),
      nutrient('energy-kcal', 'Energy (kcal)', unit: 'kcal'),
      nutrient(
        'fat',
        'Fat',
        sub: <Object?>[
          nutrient('saturated-fat', 'Saturated fat'),
          nutrient('trans-fat', 'Trans fat', important: false),
          nutrient('cholesterol', 'Cholesterol', important: false, unit: 'mg'),
        ],
      ),
      nutrient(
        'carbohydrates',
        'Carbohydrates',
        sub: <Object?>[
          nutrient('sugars', 'Sugars'),
          nutrient('added-sugars', 'Added sugars', important: false),
          nutrient('starch', 'Starch', important: false),
        ],
      ),
      nutrient('fiber', 'Fiber'),
      nutrient('proteins', 'Proteins'),
      nutrient('salt', 'Salt'),
      nutrient('sodium', 'Sodium', important: false),
      nutrient('alcohol', 'Alcohol', important: false, unit: '% vol'),
      nutrient(
        'vitamin-c',
        'Vitamin C (ascorbic acid)',
        important: false,
        unit: 'mg',
      ),
      nutrient('calcium', 'Calcium', important: false, unit: 'mg'),
      nutrient('iron', 'Iron', important: false, unit: 'mg'),
    ],
  });
}

/// GET /api/v3/taxonomy_suggestions: a few entries of the taxonomy asked for
/// that contain what was typed.
http.Response? _suggestions(http.Request request) {
  if (request.url.path != '/api/v3/taxonomy_suggestions') {
    return null;
  }
  const Map<String, List<String>> known = <String, List<String>>{
    'labels': <String>[
      'Organic',
      'EU Organic',
      'Fair trade',
      'Vegan',
      'Gluten-free',
    ],
    'categories': <String>[
      'Soups',
      'Vegetable soups',
      'Butternut squash soups',
      'Meals',
    ],
    'stores': <String>['Whole Foods', 'Carrefour', 'Trader Joe\'s'],
    'countries': <String>['United States', 'France', 'Germany'],
    'origins': <String>['France', 'Spain', 'Italy'],
    'allergens': <String>['Celery', 'Milk', 'Gluten', 'Nuts'],
  };
  final String typed = (request.url.queryParameters['string'] ?? '')
      .toLowerCase();
  return FakeServers.json(<String, Object?>{
    'suggestions': <String>[
      for (final String entry
          in known[request.url.queryParameters['tagtype']] ?? <String>[])
        if (entry.toLowerCase().contains(typed)) entry,
    ],
  });
}

/// The search term the server finds nothing for.
const String kNoResultTerm = 'zzyzx';

/// POST /cgi/search.pl: every complete product, whatever the terms, except
/// for [kNoResultTerm].
http.Response? _search(http.Request request) {
  if (request.url.path != '/cgi/search.pl') {
    return null;
  }
  final String terms =
      (request.method == 'POST'
          ? request.bodyFields['search_terms']
          : request.url.queryParameters['search_terms']) ??
      '';
  final List<Object?> products = terms.contains(kNoResultTerm)
      ? <Object?>[]
      : <Object?>[
          for (final String barcode in kListBarcodes) productJson(barcode),
        ];
  return FakeServers.json(<String, Object?>{
    'count': products.length,
    'page': 1,
    'page_count': products.length,
    'page_size': 50,
    'skip': 0,
    'products': products,
  });
}

/// Open Prices: three prices for the complete product, none for the others.
http.Response? _prices(http.Request request) {
  if (request.url.host != 'prices.openfoodfacts.org' ||
      request.method != 'GET' ||
      request.url.path != '/api/v1/prices') {
    return null;
  }
  // Without a product: the newest prices of everybody (the same three).
  final String? barcode = request.url.queryParameters['product_code'];
  final List<Object?> items = barcode == kComplete || barcode == null
      ? <Object?>[
          _price(
            1,
            kComplete,
            amount: 3.49,
            date: '2026-11-02',
            owner: 'kiliweb',
          ),
          _price(
            2,
            kComplete,
            amount: 2.99,
            withoutDiscount: 3.79,
            date: '2026-10-18',
            owner: 'a11y-tester',
          ),
          _price(
            3,
            kComplete,
            amount: 3.79,
            date: '2026-09-27',
            owner: 'teolemon',
          ),
        ]
      : <Object?>[];
  return FakeServers.json(<String, Object?>{
    'items': items,
    'total': items.length,
    'page': 1,
    'size': 10,
    'pages': 1,
  });
}

/// Folksonomy Engine: two free-form properties for the complete product.
http.Response? _folksonomy(http.Request request) {
  final List<String> segments = request.url.pathSegments;
  if (request.url.host != 'api.folksonomy.openfoodfacts.org' ||
      request.method != 'GET' ||
      segments.length != 2 ||
      segments[0] != 'product') {
    return null;
  }
  Map<String, Object?> tag(String k, String v) => <String, Object?>{
    'product': segments[1],
    'k': k,
    'v': v,
    'owner': '',
    'version': 1,
    'editor': 'a11y-tester',
    'last_edit': '2026-10-21T09:14:03.000000',
    'comment': '',
  };
  return FakeServers.json(
    segments[1] == kComplete
        ? <Object?>[
            tag('packaging:has_character', 'no'),
            tag('shelf_life:days_after_opening', '3'),
          ]
        : <Object?>[],
  );
}

/// Robotoff: one question for the complete product, none for the others.
http.Response? _robotoff(http.Request request) {
  final List<String> segments = request.url.pathSegments;
  if (request.url.host != 'robotoff.openfoodfacts.org' ||
      request.method != 'GET' ||
      segments.length < 3 ||
      segments[2] != 'questions') {
    return null;
  }
  // With no barcode: the questions of the "Hunger Games" (the same one).
  if (segments.length == 4 && segments[3] != kComplete) {
    return FakeServers.json(<String, Object?>{
      'status': 'no_questions',
      'questions': <Object?>[],
    });
  }
  return FakeServers.json(<String, Object?>{
    'status': 'found',
    'questions': <Object?>[
      <String, Object?>{
        'barcode': kComplete,
        'type': 'add-binary',
        'value': 'Butternut squash soups',
        'question': 'Does the product belong to this category?',
        'insight_id': '5f1e2b3c-7a4d-4a57-9d55-2f0c3a8f6e11',
        'insight_type': 'category',
        'value_tag': 'en:butternut-squash-soups',
        'source_image_url': 'https://images.openfoodfacts.org/images/products/932/700/674/81501/front_en.2607.400.jpg',
      },
    ],
  });
}

/// Product photos: one drawn picture of a jar, the same for every product
/// and every size.
http.Response? _photo(http.Request request) {
  final String path = request.url.path.toLowerCase();
  if (request.method != 'GET' ||
      !(path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.png') ||
          path.endsWith('.webp'))) {
    return null;
  }
  return http.Response.bytes(
    File('test/a11y/support/product_photo.png').readAsBytesSync(),
    200,
    headers: <String, String>{'content-type': 'image/png'},
  );
}

/// Pictograms the app does not ship, answered with a grey square.
final Set<String> standInSvgs = <String>{};

const Map<String, String> _svg = <String, String>{
  'content-type': 'image/svg+xml; charset=utf-8',
};

const Map<String, String> _json = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};

const String _greySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
    '<rect width="100" height="100" fill="#9e9e9e"/></svg>';
