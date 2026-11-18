import 'api_client.dart';

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

bool _asBool(Object? value) => value == true;

class LkmPointsBalance {
  const LkmPointsBalance({
    required this.userId,
    required this.balance,
    this.level = 1,
    this.nextLevelPoints = 100,
    this.levelProgress = 0,
  });

  final String userId;
  final int balance;
  final int level;
  final int nextLevelPoints;
  final int levelProgress;

  factory LkmPointsBalance.fromJson(Map<String, dynamic> json) =>
      LkmPointsBalance(
        userId: '${json['user_id'] ?? ''}',
        balance: _asInt(json['balance']),
        level: _asInt(json['level']),
        nextLevelPoints: _asInt(json['next_level_points']),
        levelProgress: _asInt(json['level_progress']),
      );
}

class LkmPointsLedgerEntry {
  const LkmPointsLedgerEntry({
    required this.id,
    required this.delta,
    required this.balanceAfter,
    required this.reason,
    required this.refType,
    required this.refId,
    required this.createdAt,
  });

  final String id;
  final int delta;
  final int balanceAfter;

  /// Stable server key (`checkin`, `transfer_out`, ...); the UI maps it to a
  /// localized label and falls back to the raw key for unknown values.
  final String reason;
  final String refType;
  final String refId;
  final DateTime createdAt;

  factory LkmPointsLedgerEntry.fromJson(Map<String, dynamic> json) {
    final parsed = DateTime.tryParse('${json['created_at'] ?? ''}');
    return LkmPointsLedgerEntry(
      id: '${json['id'] ?? ''}',
      delta: _asInt(json['delta']),
      balanceAfter: _asInt(json['balance_after']),
      reason: '${json['reason'] ?? ''}',
      refType: '${json['ref_type'] ?? ''}',
      refId: '${json['ref_id'] ?? ''}',
      createdAt: (parsed ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal(),
    );
  }
}

class LkmPointsLeaderboardEntry {
  const LkmPointsLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.balance,
    required this.title,
  });

  final String userId;
  final String displayName;
  final int balance;

  /// Title key suffix (`active`, `hardcore`, ...) — see
  /// `contributionData.leaderboard.titles.*`.
  final String title;

  factory LkmPointsLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LkmPointsLeaderboardEntry(
        userId: '${json['user_id'] ?? ''}',
        displayName: '${json['display_name'] ?? ''}',
        balance: _asInt(json['balance']),
        title: '${json['title'] ?? ''}',
      );
}

class LkmPointsAchievement {
  const LkmPointsAchievement({
    required this.id,
    required this.key,
    required this.category,
    required this.icon,
    required this.nameKey,
    required this.descKey,
    required this.type,
    required this.threshold,
    required this.rewardPoints,
    required this.progress,
    required this.unlocked,
  });

  final String id;
  final String key;
  final String category;

  /// Iconify/Tabler name (`tabler:star`); the UI maps it to a Material symbol.
  final String icon;
  final String nameKey;
  final String descKey;
  final String type;
  final int threshold;
  final int rewardPoints;
  final int progress;
  final bool unlocked;

  double get progressRatio => threshold > 0
      ? (progress / threshold).clamp(0.0, 1.0)
      : 0.0;

  factory LkmPointsAchievement.fromJson(Map<String, dynamic> json) =>
      LkmPointsAchievement(
        id: '${json['id'] ?? ''}',
        key: '${json['key'] ?? ''}',
        category: '${json['category'] ?? ''}',
        icon: '${json['icon'] ?? ''}',
        nameKey: '${json['name_key'] ?? ''}',
        descKey: '${json['desc_key'] ?? ''}',
        type: '${json['type'] ?? ''}',
        threshold: _asInt(json['threshold']),
        rewardPoints: _asInt(json['reward_points']),
        progress: _asInt(json['progress']),
        unlocked: _asBool(json['unlocked']),
      );
}

class LkmPointsTask {
  const LkmPointsTask({
    required this.id,
    required this.key,
    required this.titleKey,
    required this.descKey,
    required this.category,
    required this.requirementCount,
    required this.rewardPoints,
    required this.currentProgress,
    required this.completed,
  });

  final String id;
  final String key;
  final String titleKey;
  final String descKey;
  final String category;
  final int requirementCount;
  final int rewardPoints;
  final int currentProgress;
  final bool completed;

  double get progressRatio => requirementCount > 0
      ? (currentProgress / requirementCount).clamp(0.0, 1.0)
      : 0.0;

  factory LkmPointsTask.fromJson(Map<String, dynamic> json) => LkmPointsTask(
    id: '${json['id'] ?? ''}',
    key: '${json['key'] ?? ''}',
    titleKey: '${json['title_key'] ?? ''}',
    descKey: '${json['desc_key'] ?? ''}',
    category: '${json['category'] ?? ''}',
    requirementCount: _asInt(json['requirement_count']),
    rewardPoints: _asInt(json['reward_points']),
    currentProgress: _asInt(json['current_progress']),
    completed: _asBool(json['completed']),
  );
}

class LkmPointsExchangeItem {
  const LkmPointsExchangeItem({
    required this.id,
    required this.key,
    required this.nameKey,
    required this.descKey,
    required this.pointsCost,
    required this.stock,
    required this.isVirtual,
  });

  final String id;
  final String key;
  final String nameKey;
  final String descKey;
  final int pointsCost;

  /// `-1` means unlimited, `0` means sold out.
  final int stock;
  final bool isVirtual;

  bool get soldOut => stock == 0;
  bool get lowStock => stock > 0 && stock < 20;

  factory LkmPointsExchangeItem.fromJson(Map<String, dynamic> json) =>
      LkmPointsExchangeItem(
        id: '${json['id'] ?? ''}',
        key: '${json['key'] ?? ''}',
        nameKey: '${json['name_key'] ?? ''}',
        descKey: '${json['desc_key'] ?? ''}',
        pointsCost: _asInt(json['points_cost']),
        stock: _asInt(json['stock']),
        isVirtual: _asBool(json['is_virtual']),
      );
}

class LkmCheckInTip {
  const LkmCheckInTip({
    required this.title,
    required this.content,
    required this.isPositive,
  });

  final String title;
  final String content;
  final bool isPositive;

  factory LkmCheckInTip.fromJson(Map<String, dynamic> json) => LkmCheckInTip(
    title: '${json['title'] ?? ''}',
    content: '${json['content'] ?? ''}',
    isPositive: _asBool(json['is_positive']),
  );
}

class LkmCheckInFortune {
  const LkmCheckInFortune({
    required this.version,
    required this.poem,
    required this.summary,
    required this.summaryDetail,
    required this.wish,
    required this.love,
    required this.study,
    required this.career,
    required this.health,
    required this.lostItem,
    required this.luckyColor,
    required this.luckyDirection,
    required this.luckyTime,
    required this.luckyItem,
    required this.luckyAction,
    required this.avoidAction,
    required this.ritual,
  });

  final int version;
  final String poem;
  final String summary;
  final String? summaryDetail;
  final String wish;
  final String love;
  final String study;
  final String career;
  final String health;
  final String lostItem;
  final String luckyColor;
  final String luckyDirection;
  final String luckyTime;
  final String luckyItem;
  final String luckyAction;
  final String avoidAction;
  final String ritual;

  factory LkmCheckInFortune.fromJson(Map<String, dynamic> json) =>
      LkmCheckInFortune(
        version: _asInt(json['version']),
        poem: '${json['poem'] ?? ''}',
        summary: '${json['summary'] ?? ''}',
        summaryDetail: json['summary_detail'] as String?,
        wish: '${json['wish'] ?? ''}',
        love: '${json['love'] ?? ''}',
        study: '${json['study'] ?? ''}',
        career: '${json['career'] ?? ''}',
        health: '${json['health'] ?? ''}',
        lostItem: '${json['lost_item'] ?? ''}',
        luckyColor: '${json['lucky_color'] ?? ''}',
        luckyDirection: '${json['lucky_direction'] ?? ''}',
        luckyTime: '${json['lucky_time'] ?? ''}',
        luckyItem: '${json['lucky_item'] ?? ''}',
        luckyAction: '${json['lucky_action'] ?? ''}',
        avoidAction: '${json['avoid_action'] ?? ''}',
        ritual: '${json['ritual'] ?? ''}',
      );
}

class LkmCheckInResult {
  const LkmCheckInResult({
    required this.id,
    required this.level,
    required this.tips,
    required this.fortuneReport,
    required this.createdAt,
  });

  final String id;
  final int level;
  final List<LkmCheckInTip> tips;
  final LkmCheckInFortune fortuneReport;
  final DateTime createdAt;

  factory LkmCheckInResult.fromJson(Map<String, dynamic> json) {
    final tips = json['tips'];
    final report = json['fortune_report'];
    return LkmCheckInResult(
      id: '${json['id'] ?? ''}',
      level: _asInt(json['level']),
      tips: tips is List
          ? tips
                .whereType<Map>()
                .map((e) => LkmCheckInTip.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const [],
      fortuneReport: LkmCheckInFortune.fromJson(
        report is Map ? Map<String, dynamic>.from(report) : const {},
      ),
      createdAt:
          DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal() ??
          DateTime.now(),
    );
  }
}

class LkmCheckInHistoryItem {
  const LkmCheckInHistoryItem({required this.date, required this.result});

  final DateTime date;
  final LkmCheckInResult result;

  factory LkmCheckInHistoryItem.fromJson(Map<String, dynamic> json) {
    final rawDate = DateTime.tryParse('${json['date'] ?? ''}');
    return LkmCheckInHistoryItem(
      date: rawDate ?? DateTime.now(),
      result: LkmCheckInResult.fromJson(
        json['result'] is Map
            ? Map<String, dynamic>.from(json['result'] as Map)
            : const {},
      ),
    );
  }
}

class LkmPointsCheckin {
  const LkmPointsCheckin({
    required this.success,
    required this.earned,
    required this.checkinStreak,
    required this.todayChecked,
    this.backdated = false,
    this.result,
  });

  final bool success;
  final int earned;
  final int checkinStreak;
  final bool todayChecked;
  final bool backdated;
  final LkmCheckInResult? result;

  factory LkmPointsCheckin.fromJson(Map<String, dynamic> json) {
    final result = json['result'];
    return LkmPointsCheckin(
      success: _asBool(json['success']),
      earned: _asInt(json['earned']),
      checkinStreak: _asInt(json['checkin_streak']),
      todayChecked: _asBool(json['today_checked']),
      backdated: _asBool(json['backdated']),
      result: result is Map
          ? LkmCheckInResult.fromJson(Map<String, dynamic>.from(result))
          : null,
    );
  }
}

/// Read surface for `/api/v1/points` (balance, ledger, leaderboard,
/// achievements, tasks, exchange items, daily check-in).
///
/// The exchange list is read-only: the service exposes no redemption endpoint
/// yet, so the desktop UI points users at the website instead of faking a
/// purchase.
class PointsApi {
  const PointsApi(this._client);

  final ApiClient _client;

  Future<LkmPointsBalance> balance() async {
    final data = await _client.getObject('/points/me');
    return LkmPointsBalance.fromJson(data);
  }

  Future<ApiPage<LkmPointsLedgerEntry>> ledger({
    int page = 1,
    int limit = 20,
  }) => _client.getPage(
    '/points/me/ledger',
    query: {'page': page, 'limit': limit},
    parseItem: LkmPointsLedgerEntry.fromJson,
  );

  Future<LkmPointsCheckin> checkin({DateTime? date}) async {
    final data = await _client.post(
      '/points/checkin',
      query: date == null
          ? null
          : {'date': date.toIso8601String().substring(0, 10)},
    );
    if (data is! Map) {
      throw const ApiException(
        code: ApiCode.invalidInput,
        message: '打卡响应格式异常',
        method: 'POST',
        path: '/points/checkin',
      );
    }
    return LkmPointsCheckin.fromJson(Map<String, dynamic>.from(data));
  }

  /// Today's draw, or null when the signed-in user has not drawn yet.
  Future<LkmCheckInResult?> todayCheckin() async {
    final data = await _client.get('/points/checkin/today');
    if (data is! Map) return null;
    return LkmCheckInResult.fromJson(Map<String, dynamic>.from(data));
  }

  /// One month of draws (`GET /points/checkin/history`).
  Future<List<LkmCheckInHistoryItem>> checkinHistory({
    required int year,
    required int month,
  }) async {
    final data = await _client.get(
      '/points/checkin/history',
      query: {'year': year, 'month': month},
    );
    if (data is! Map) return const [];
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => LkmCheckInHistoryItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// [period] is `total` / `daily` / `weekly`.
  Future<ApiPage<LkmPointsLeaderboardEntry>> leaderboard({
    String period = 'total',
    int limit = 50,
  }) => _client.getPage(
    '/points/leaderboard',
    query: {'period': period, 'limit': limit},
    parseItem: LkmPointsLeaderboardEntry.fromJson,
  );

  Future<List<LkmPointsAchievement>> achievements() => _client.getList(
    '/points/achievements',
    parseItem: LkmPointsAchievement.fromJson,
  );

  Future<List<LkmPointsTask>> tasks() =>
      _client.getList('/points/tasks', parseItem: LkmPointsTask.fromJson);

  Future<List<LkmPointsExchangeItem>> exchangeItems() => _client.getList(
    '/points/exchange-items',
    parseItem: LkmPointsExchangeItem.fromJson,
  );
}
