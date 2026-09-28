/// Models for the profile screen.
library;

/// A signed-in device (a personal access token), as `/auth/sessions` lists it.
class ProfileSession {
  ProfileSession.fromJson(Map<String, dynamic> json)
    : id = json['id'] is num ? (json['id'] as num).toInt() : 0,
      device = '${json['device'] ?? ''}',
      lastUsedAt = DateTime.tryParse(
        '${json['last_used_at'] ?? ''}',
      )?.toLocal(),
      createdAt = DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
      isCurrent = json['is_current'] == true;

  final int id;
  final String device;
  final DateTime? lastUsedAt, createdAt;
  final bool isCurrent;
}
