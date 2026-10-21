import '../../shared/services/app_events.dart';
import 'mutation_meta.dart';
import 'room_rules.dart';

// Linen and amenities, laundry, supply requests and the minibar. Every
// stock change goes through [moveStock]: one movement row (the usage log),
// the low-stock alert, in the caller's transaction.

const supplyCategories = ['linge', 'accueil', 'entretien', 'minibar'];
const supplyCategoryLabels = {
  'linge': 'Linge',
  'accueil': 'Produits d’accueil',
  'entretien': 'Produits d’entretien',
  'minibar': 'Minibar',
};

/// The type of an item created before types existed, from its name.
String categoryFromName(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'drap|serviette|taie|peignoir|housse|linge|tapis de bain')
      .hasMatch(n)) {
    return 'linge';
  }
  if (RegExp(r'savon|gel|shampo|accueil|dentifrice|brosse|bonnet|lotion')
      .hasMatch(n)) {
    return 'accueil';
  }
  return 'entretien';
}

typedef Fail = Never Function(String message, [int status]);

List<Map<String, dynamic>> listOf(Map<String, dynamic> s, String key) =>
    (s[key] as List? ?? (s[key] = <dynamic>[])).cast<Map<String, dynamic>>();

Map<String, dynamic>? supplyById(Map<String, dynamic> s, Object? id) =>
    listOf(s, 'supplies').where((x) => x['id'] == id).firstOrNull;

int? floorOf(String? room) =>
    room == null || room.isEmpty ? null : int.tryParse(room.substring(0, 1));

/// Changes the stock of [supply] by [delta] and logs it. Refuses a stock
/// below zero (409). Alerts once when the stock falls to its minimum.
void moveStock(
  Map<String, dynamic> s,
  Map<String, dynamic> supply,
  int delta, {
  required String reason,
  required Map<String, dynamic> actor,
  required DateTime now,
  required Fail fail,
  String? room,
  String? ref,
  int? quantity,
}) {
  final previous = supply['quantity'] as int;
  final next = previous + delta;
  if (next < 0) {
    fail(
      'Stock insuffisant : ${supply['name']} ($previous ${supply['unit']} disponibles).',
      409,
    );
  }
  if (next > 1000000) fail('Quantité trop élevée.');
  supply['quantity'] = next;
  if (delta != 0) bumpVersion(supply);
  final minimum = supply['minimum'] as int;
  if (previous > minimum && next <= minimum) {
    addNotification(
      s,
      title: next == 0 ? 'Rupture de stock' : 'Stock bas',
      message: next == 0
          ? '${supply['name']} : stock épuisé (minimum $minimum). Pensez à réapprovisionner.'
          : '${supply['name']} : il reste $next ${supply['unit']} (minimum $minimum). Pensez à réapprovisionner.',
      roomNumber: '',
      audience: 'supervisor',
    );
  }
  listOf(s, 'stockMovements').add({
    'id': uuidV4(),
    'supply_id': supply['id'],
    'supply_name': supply['name'],
    'delta': delta,
    'quantity': quantity ?? delta.abs(),
    'reason': reason,
    'room_number': room,
    'floor': floorOf(room),
    'actor_id': actor['id'],
    'actor_name': actor['name'],
    'ref_id': ref,
    'at': now.toIso8601String(),
  });
}

/// Type and price of a stock item from a create or update body.
({String category, int? priceCents}) supplyFields(
  Map<String, dynamic> body,
  Fail fail, {
  String fallback = 'entretien',
}) {
  final category = body['category'] ?? fallback;
  if (!supplyCategories.contains(category)) fail('Type d’article inconnu.');
  final price = body['priceCents'];
  if (category == 'minibar') {
    if (price is! int || price < 1 || price > 100000) {
      fail('Prix de vente de 0,01 à 1 000 €.');
    }
    return (category: 'minibar', priceCents: price);
  }
  return (category: category as String, priceCents: null);
}

/// Items still waiting for a laundry return or a supply delivery.
bool supplyInUse(Map<String, dynamic> s, Object? id) =>
    listOf(s, 'laundry').any(
      (b) =>
          b['status'] == 'sent' &&
          (b['lines'] as List).any((l) => l['supply_id'] == id),
    ) ||
    listOf(s, 'requests').any(
      (r) =>
          ['requested', 'approved', 'prepared'].contains(r['status']) &&
          (r['lines'] as List).any((l) => l['supply_id'] == id),
    );

/// The guest's stay in [room] now (from the reservation events), if any.
Map<String, dynamic>? openStay(Map<String, dynamic> s, String room) =>
    listOf(s, 'stays')
        .where((x) => x['room_number'] == room && x['checked_out_at'] == null)
        .lastOrNull;

void checkIn(Map<String, dynamic> s, String room, String guest, DateTime now) {
  checkOut(s, room, now);
  listOf(s, 'stays').add({
    'id': uuidV4(),
    'room_number': room,
    'guest_name': guest,
    'checked_in_at': now.toIso8601String(),
    'checked_out_at': null,
  });
}

void checkOut(Map<String, dynamic> s, String room, DateTime now) =>
    openStay(s, room)?['checked_out_at'] = now.toIso8601String();

/// The quantity billed for a consumption, its posted corrections included.
int effectiveQuantity(Map<String, dynamic> s, Map<String, dynamic> entry) =>
    (entry['quantity'] as int) +
    listOf(s, 'minibar')
        .where(
          (c) => c['corrects_id'] == entry['id'] && c['status'] != 'cancelled',
        )
        .fold(0, (sum, c) => sum + (c['quantity'] as int));

class InventoryRules {
  final Map<String, dynamic> s;
  final Map<String, dynamic> actor;
  final DateTime now;
  final Fail fail;
  final List<AppEvent> announce;
  InventoryRules(this.s, this.actor, this.now, this.fail, this.announce);

  bool get supervisor => actor['role'] == 'supervisor';
  String get stamp => now.toIso8601String();

  void require(bool value, String message, [int status = 400]) {
    if (!value) fail(message, status);
  }

  int count(Object? value, int min, int max, String message) {
    require(value is int && value >= min && value <= max, message);
    return value as int;
  }

  String text(Object? value, int max, String message) {
    require(
      value is String && value.trim().isNotEmpty && value.trim().length <= max,
      message,
    );
    return (value as String).trim();
  }

  String? note(Object? value) {
    require(
      value == null || (value is String && value.length <= 200),
      'Note de 200 caractères maximum.',
    );
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Map<String, dynamic> room(Object? number, {bool own = true}) {
    final room = number is String ? activeRoom(s, number) : null;
    require(room != null, 'Choisissez une chambre active.');
    require(
      !own || supervisor || room!['employeeId'] == actor['id'],
      'Cette chambre ne vous est pas attribuée.',
      403,
    );
    return room!;
  }

  void version(Map<String, dynamic> row, Map<String, dynamic> body) => require(
    body['version'] == row['version'],
    'Ces données ont changé. Actualisez.',
    409,
  );

  /// `{supplyId, quantity}` lines: known items of an allowed type, once each.
  List<(Map<String, dynamic>, int)> lines(
    Object? value,
    bool Function(String category) allowed,
    String wrongType, {
    int max = 10000,
  }) {
    require(
      value is List && value.isNotEmpty && value.length <= 30,
      'Ajoutez au moins un article.',
    );
    final seen = <Object?>{};
    return [
      for (final line in value as List)
        () {
          require(line is Map, 'Ligne invalide.');
          final supply = supplyById(s, line['supplyId']);
          require(supply != null, 'Article introuvable.', 404);
          require(allowed(supply!['category'] as String? ?? ''), wrongType);
          require(seen.add(supply['id']), 'Un article apparaît deux fois.');
          return (
            supply,
            count(line['quantity'], 1, max, 'Quantité de 1 à $max.'),
          );
        }(),
    ];
  }

  void notifyAgent(String agentId, String title, String message) =>
      addNotification(
        s,
        title: title,
        message: message,
        roomNumber: '',
        audience: 'agent',
        recipient: agentId,
      );

  /// Handles `/v1/supplies/<id>/use` and the laundry, requests and minibar
  /// families. Returns false for any other path.
  bool apply(
    String family,
    String key,
    String action,
    Map<String, dynamic> body,
  ) {
    switch (family) {
      case 'supplies' when action == 'use':
        _use(key, body);
      case 'laundry':
        require(supervisor, 'Blanchisserie gérée par la gouvernante.', 403);
        key == 'new' ? _send(action, body) : _return(key, action, body);
      case 'requests':
        key == 'new' ? _request(action, body) : _process(key, action, body);
      case 'minibar':
        _minibar(key, action, body);
      default:
        return false;
    }
    return true;
  }

  // ------------------------------------------------------------- usage log
  void _use(String id, Map<String, dynamic> body) {
    final supply = supplyById(s, id);
    if (supply == null) fail('Article introuvable.', 404);
    require(
      supply['category'] != 'minibar',
      'Le minibar se réapprovisionne depuis la fiche de la chambre.',
    );
    final number = room(body['roomNumber'])['number'] as String;
    final quantity = count(body['quantity'], 1, 1000, 'Quantité de 1 à 1000.');
    moveStock(
      s,
      supply,
      -quantity,
      reason: 'usage',
      actor: actor,
      now: now,
      fail: fail,
      room: number,
    );
  }

  // --------------------------------------------------------------- laundry
  void _send(String action, Map<String, dynamic> body) {
    require(action == 'send', 'Action inconnue.');
    final items = lines(
      body['lines'],
      (c) => c == 'linge',
      'Seul le linge part en blanchisserie.',
    );
    final id = uuidV4();
    for (final (supply, quantity) in items) {
      moveStock(
        s,
        supply,
        -quantity,
        reason: 'laundry_out',
        actor: actor,
        now: now,
        fail: fail,
        ref: id,
      );
    }
    listOf(s, 'laundry').insert(0, {
      'id': id,
      'status': 'sent',
      'note': note(body['note']),
      'sent_at': stamp,
      'sent_by_name': actor['name'],
      'returned_at': null,
      'returned_by_name': null,
      'version': 1,
      'lines': [
        for (final (supply, quantity) in items)
          {
            'id': uuidV4(),
            'supply_id': supply['id'],
            'supply_name': supply['name'],
            'unit': supply['unit'],
            'sent': quantity,
            'received': null,
            'damaged': null,
            'lost': null,
          },
      ],
    });
  }

  void _return(String id, String action, Map<String, dynamic> body) {
    final batch = listOf(s, 'laundry').where((b) => b['id'] == id).firstOrNull;
    if (batch == null) fail('Envoi introuvable.', 404);
    version(batch, body);
    require(action == 'return', 'Action inconnue.');
    require(batch['status'] == 'sent', 'Ce linge est déjà revenu.', 409);
    final given = body['lines'];
    require(given is List, 'Indiquez le linge reçu.');
    final byItem = {
      for (final l in given as List)
        if (l is Map) l['supplyId']: l,
    };
    final batchLines = (batch['lines'] as List).cast<Map<String, dynamic>>();
    require(
      byItem.length == batchLines.length &&
          batchLines.every((l) => byItem.containsKey(l['supply_id'])),
      'Indiquez le retour de chaque article envoyé.',
    );
    for (final line in batchLines) {
      final r = byItem[line['supply_id']]!;
      final sent = line['sent'] as int;
      final received = count(
        r['received'],
        0,
        sent,
        'Quantité reçue invalide.',
      );
      final damaged = count(r['damaged'], 0, sent, 'Quantité abîmée invalide.');
      final lost = count(r['lost'], 0, sent, 'Quantité perdue invalide.');
      require(
        received + damaged + lost == sent,
        '${line['supply_name']} : reçu + abîmé + perdu doit faire $sent.',
      );
      line['received'] = received;
      line['damaged'] = damaged;
      line['lost'] = lost;
      final supply = supplyById(s, line['supply_id']);
      if (supply == null) continue; // item deleted meanwhile: nothing to add
      void log(String reason, int n, int delta) {
        if (n == 0) return;
        moveStock(
          s,
          supply,
          delta,
          reason: reason,
          actor: actor,
          now: now,
          fail: fail,
          ref: id,
          quantity: n,
        );
      }

      log('laundry_in', received, received);
      // Written off: logged, the stock already went out with the batch.
      log('laundry_damaged', damaged, 0);
      log('laundry_lost', lost, 0);
    }
    batch['status'] = 'returned';
    batch['returned_at'] = stamp;
    batch['returned_by_name'] = actor['name'];
    bumpVersion(batch);
  }

  // ------------------------------------------------------ supply requests
  void _request(String action, Map<String, dynamic> body) {
    require(action == 'create', 'Action inconnue.');
    require(!supervisor, 'Les demandes sont faites par les agents.', 403);
    final items = lines(
      body['lines'],
      (c) => c != 'minibar',
      'Le minibar ne se commande pas ici.',
      max: 500,
    );
    final text = note(body['note']);
    listOf(s, 'requests').insert(0, {
      'id': uuidV4(),
      'status': 'requested',
      'agent_id': actor['id'],
      'agent_name': actor['name'],
      'note': text,
      'created_at': stamp,
      'approved_at': null,
      'prepared_at': null,
      'delivered_at': null,
      'refused_at': null,
      'processed_by_name': null,
      'refusal_reason': null,
      'version': 1,
      'lines': [
        for (final (supply, quantity) in items)
          {
            'id': uuidV4(),
            'supply_id': supply['id'],
            'supply_name': supply['name'],
            'unit': supply['unit'],
            'requested': quantity,
            'approved': quantity,
          },
      ],
    });
    addNotification(
      s,
      title: 'Demande de fournitures',
      message:
          '${actor['name']} : ${[for (final (x, n) in items) '${x['name']} × $n'].join(', ')}',
      roomNumber: '',
      audience: 'supervisor',
    );
  }

  void _process(String id, String action, Map<String, dynamic> body) {
    require(supervisor, 'Demandes traitées par la gouvernante.', 403);
    final request = listOf(
      s,
      'requests',
    ).where((r) => r['id'] == id).firstOrNull;
    if (request == null) fail('Demande introuvable.', 404);
    version(request, body);
    final status = request['status'];
    final requestLines = (request['lines'] as List)
        .cast<Map<String, dynamic>>();
    final agent = request['agent_id'] as String;
    String summary() => [
      for (final l in requestLines)
        if ((l['approved'] as int) > 0)
          '${l['supply_name']} × ${l['approved']}',
    ].join(', ');
    switch (action) {
      case 'approve':
        require(status == 'requested', 'Demande déjà traitée.', 409);
        final adjusted = body['lines'];
        if (adjusted != null) {
          require(adjusted is List, 'Quantités invalides.');
          for (final a in adjusted as List) {
            final line = requestLines
                .where((l) => a is Map && l['supply_id'] == a['supplyId'])
                .firstOrNull;
            require(line != null, 'Article absent de la demande.');
            line!['approved'] = count(
              a['quantity'],
              0,
              line['requested'] as int,
              'Quantité accordée de 0 à ${line['requested']}.',
            );
          }
        }
        require(
          requestLines.any((l) => (l['approved'] as int) > 0),
          'Accordez au moins un article, ou refusez la demande.',
        );
        final short = [
          for (final l in requestLines)
            if (((supplyById(s, l['supply_id'])?['quantity'] as int?) ?? 0) <
                (l['approved'] as int))
              l['supply_name'],
        ];
        request['status'] = 'approved';
        request['approved_at'] = stamp;
        notifyAgent(
          agent,
          'Demande approuvée',
          [
            summary(),
            if (short.isNotEmpty) 'Stock insuffisant : ${short.join(', ')}',
          ].join(' · '),
        );
      case 'prepare':
        require(status == 'approved', 'Approuvez la demande d’abord.', 409);
        request['status'] = 'prepared';
        request['prepared_at'] = stamp;
        notifyAgent(
          agent,
          'Demande préparée',
          '${summary()} · à récupérer à la lingerie',
        );
      case 'deliver':
        require(status == 'prepared', 'Préparez la demande d’abord.', 409);
        for (final line in requestLines) {
          final n = line['approved'] as int;
          if (n == 0) continue;
          final supply = supplyById(s, line['supply_id']);
          if (supply == null) {
            fail('${line['supply_name']} n’est plus en stock.', 409);
          }
          moveStock(
            s,
            supply,
            -n,
            reason: 'request',
            actor: actor,
            now: now,
            fail: fail,
            ref: id,
          );
        }
        request['status'] = 'delivered';
        request['delivered_at'] = stamp;
        notifyAgent(agent, 'Fournitures livrées', summary());
      case 'refuse':
        require(
          ['requested', 'approved', 'prepared'].contains(status),
          'Demande déjà traitée.',
          409,
        );
        request['refusal_reason'] = text(
          body['reason'],
          200,
          'Indiquez la raison du refus (200 caractères maximum).',
        );
        request['status'] = 'refused';
        request['refused_at'] = stamp;
        notifyAgent(
          agent,
          'Demande refusée',
          request['refusal_reason'] as String,
        );
      default:
        fail('Action inconnue.');
    }
    request['processed_by_name'] = actor['name'];
    bumpVersion(request);
  }

  // ---------------------------------------------------------------- minibar
  Map<String, dynamic> _consumption(String id) {
    final entry = listOf(s, 'minibar').where((c) => c['id'] == id).firstOrNull;
    if (entry == null) fail('Consommation introuvable.', 404);
    return entry;
  }

  void _minibar(String key, String action, Map<String, dynamic> body) {
    switch (action) {
      case 'record':
        require(key == 'new', 'Action inconnue.');
        final number = room(body['roomNumber'])['number'] as String;
        final item = supplyById(s, body['itemId']);
        require(
          item?['category'] == 'minibar',
          'Article de minibar inconnu.',
          404,
        );
        final quantity = count(body['quantity'], 1, 50, 'Quantité de 1 à 50.');
        _addConsumption(number, item!, quantity, null);
      case 'correct':
        final entry = _consumption(key);
        version(entry, body);
        require(
          supervisor || entry['recorded_by'] == actor['id'],
          'Consommation saisie par une autre personne.',
          403,
        );
        require(
          entry['status'] == 'pending',
          'Déjà facturée : enregistrez une correction.',
          409,
        );
        final quantity = body['quantity'];
        require(
          quantity is int &&
              quantity >= (entry['corrects_id'] == null ? 0 : -50) &&
              quantity <= 50,
          'Quantité de 0 à 50.',
        );
        if (quantity == 0) {
          entry['status'] = 'cancelled';
        } else {
          entry['quantity'] = quantity;
          entry['amount_cents'] =
              (quantity as int) * (entry['unit_price_cents'] as int);
        }
        bumpVersion(entry);
      case 'compensate':
        require(supervisor, 'Correction réservée à la gouvernante.', 403);
        final entry = _consumption(key);
        version(entry, body);
        require(
          entry['status'] == 'billed' && entry['corrects_id'] == null,
          'Seule une consommation facturée se corrige ainsi.',
          409,
        );
        require(
          !listOf(
            s,
            'minibar',
          ).any((c) => c['corrects_id'] == key && c['status'] == 'pending'),
          'Une correction attend déjà d’être facturée.',
          409,
        );
        final target = count(body['quantity'], 0, 50, 'Quantité de 0 à 50.');
        final delta = target - effectiveQuantity(s, entry);
        require(delta != 0, 'La quantité facturée est déjà $target.');
        _addConsumption(
          entry['room_number'] as String,
          {
            'id': entry['supply_id'],
            'name': entry['label'],
            'priceCents': entry['unit_price_cents'],
          },
          delta,
          entry,
        );
        bumpVersion(entry);
      case 'post':
        require(supervisor, 'Facturation validée par la gouvernante.', 403);
        final number = room(key, own: false)['number'] as String;
        final ids = body['ids'];
        require(
          ids is List && ids.isNotEmpty && ids.every((i) => i is String),
          'Choisissez les consommations à facturer.',
        );
        final stay = openStay(s, number)?['id'];
        for (final id in {...ids as List}) {
          final entry = _consumption(id as String);
          require(
            entry['room_number'] == number,
            'Consommation d’une autre chambre.',
          );
          // Never published twice: billed (or cancelled) entries are skipped.
          if (entry['status'] != 'pending') continue;
          require(
            entry['stay_id'] == stay,
            'Chambre $number : le séjour a changé depuis la consommation. À transmettre à la réception.',
            409,
          );
          entry['status'] = 'billed';
          entry['billed_at'] = stamp;
          entry['billed_by_name'] = actor['name'];
          bumpVersion(entry);
          final quantity = entry['quantity'] as int;
          announce.add(
            ExtraCharged(
              number,
              label: entry['corrects_id'] == null
                  ? 'Minibar · ${entry['label']} × $quantity'
                  : 'Minibar · correction ${entry['label']} ${quantity > 0 ? '+' : ''}$quantity',
              amountCents: entry['amount_cents'] as int,
            ),
          );
        }
      case 'restock':
        final number = room(key)['number'] as String;
        for (final (item, quantity) in lines(
          body['lines'],
          (c) => c == 'minibar',
          'Seuls les articles du minibar se réapprovisionnent ici.',
          max: 50,
        )) {
          moveStock(
            s,
            item,
            -quantity,
            reason: 'minibar_restock',
            actor: actor,
            now: now,
            fail: fail,
            room: number,
          );
        }
      default:
        fail('Action inconnue.');
    }
  }

  void _addConsumption(
    String number,
    Map<String, dynamic> item,
    int quantity,
    Map<String, dynamic>? corrects,
  ) {
    final price = item['priceCents'] as int;
    listOf(s, 'minibar').insert(0, {
      'id': uuidV4(),
      'room_number': number,
      'supply_id': item['id'],
      'label': item['name'],
      'unit_price_cents': price,
      'quantity': quantity,
      'amount_cents': quantity * price,
      'status': 'pending',
      'recorded_by': actor['id'],
      'recorded_by_name': actor['name'],
      'recorded_at': stamp,
      'billed_at': null,
      'billed_by_name': null,
      'corrects_id': corrects?['id'],
      // A correction belongs to the stay of the entry it corrects.
      'stay_id': corrects == null
          ? (openStay(s, number)?['id'])
          : corrects['stay_id'],
      'version': 1,
    });
  }
}

/// Creates (no id) or updates a minibar item: the Manager's catalog. The
/// supervisor does the same through the stock rules.
void saveMinibarItem(
  Map<String, dynamic> s,
  Map<String, dynamic> body,
  Fail fail,
) {
  String text(Object? value, int max, String message) {
    if (value is! String || value.trim().isEmpty || value.trim().length > max) {
      fail(message);
    }
    return value.trim();
  }

  int amount(Object? value, String message) {
    if (value is! int || value < 0 || value > 1000000) fail(message);
    return value;
  }

  final name = text(body['name'], 80, 'Nom de 1 à 80 caractères.');
  final unit = text(body['unit'], 20, 'Unité de 1 à 20 caractères.');
  final price = supplyFields({...body, 'category': 'minibar'}, fail).priceCents;
  final minimum = amount(body['minimum'], 'Minimum invalide.');
  final supplies = listOf(s, 'supplies');
  final id = body['id'];
  if (supplies.any(
    (o) =>
        o['id'] != id &&
        (o['name'] as String).toLowerCase() == name.toLowerCase(),
  )) {
    fail('Un article porte déjà ce nom.');
  }
  if (id == null) {
    supplies.add({
      'id': 'minibar-${uuidV4()}',
      'name': name,
      'unit': unit,
      'quantity': amount(body['quantity'], 'Quantité invalide.'),
      'minimum': minimum,
      'version': 1,
      'category': 'minibar',
      'priceCents': price,
    });
    return;
  }
  final item = supplyById(s, id);
  if (item == null || item['category'] != 'minibar') {
    fail('Article de minibar introuvable.', 404);
  }
  if (body['version'] != item['version']) {
    fail('Ces données ont changé. Actualisez.', 409);
  }
  item
    ..['name'] = name
    ..['unit'] = unit
    ..['priceCents'] = price
    ..['minimum'] = minimum;
  bumpVersion(item);
}

void deleteMinibarItem(
  Map<String, dynamic> s,
  Map<String, dynamic> body,
  Fail fail,
) {
  final item = supplyById(s, body['id']);
  if (item == null || item['category'] != 'minibar') {
    fail('Article de minibar introuvable.', 404);
  }
  if (body['version'] != item['version']) {
    fail('Ces données ont changé. Actualisez.', 409);
  }
  // Consumptions keep their own label and price.
  listOf(s, 'supplies').remove(item);
}
