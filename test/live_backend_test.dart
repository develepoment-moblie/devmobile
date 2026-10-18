import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_paris/housekeeping/models/hotel_data.dart';
import 'package:nova_paris/housekeeping/models/room.dart';
import 'package:nova_paris/housekeeping/services/housekeeping_api.dart';

void main() {
  test('Real Flutter client shares assignment, cleaning, approval and stock through Node API', () async {
    final config = jsonDecode(
      File('backend/.dev/bridge.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    HousekeepingApi connect(String id) => HousekeepingApi(
      baseUrl: Uri.parse(config['url'] as String),
      tokenProvider: () async => config[id] as String,
    );
    final govApi = connect('amina'), agentApi = connect('sarah');
    final gov = HotelData(api: govApi), agent = HotelData(api: agentApi);
    addTearDown(() {
      gov.dispose();
      agent.dispose();
      govApi.close();
      agentApi.close();
    });
    await gov.refresh();
    await agent.refresh();
    final room = gov.roomByNumber('305');
    await gov.assign(room, 'sarah', 'Avant midi', true);
    await agent.refresh();
    final task = agent.roomByNumber('305');
    expect(task.employeeId, 'sarah');
    await agent.startCleaning(task);
    for (var index = 0; index < 4; index++) {
      await agent.setCheck(task, index, true);
    }
    await agent.submitCleaning(task);
    expect(task.status, RoomStatus.dirty);
    await gov.refresh();
    expect(room.cleaning, CleaningStatus.review);
    await gov.approve(room);
    await agent.refresh();
    expect(task.status, RoomStatus.ready);
    await gov.moveStock(gov.supplies.first, -2);
    await agent.refresh();
    expect(agent.supplies.first.quantity, 40);
    expect(() => agent.moveStock(agent.supplies.first, 1), throwsStateError);
    await agent.markRead([agent.notifications.first]);
    await agent.refresh();
    expect(agent.notifications.first.read, true);
  }, skip: !const bool.fromEnvironment('LIVE_HOUSEKEEPING_TEST'));
}
