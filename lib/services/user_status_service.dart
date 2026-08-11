import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef CurrentUserIdLoader = Future<String?> Function();
typedef UserStatusRowLoader =
    Future<Map<String, dynamic>?> Function(String userId);

class UserStatus {
  const UserStatus({required this.isBanned, this.banReason});

  static const active = UserStatus(isBanned: false);

  factory UserStatus.fromJson(Map<String, dynamic> json) {
    final isBanned = json['is_banned'];
    if (isBanned is! bool) {
      throw const FormatException('is_banned must be a boolean');
    }

    final rawBanReason = json['ban_reason'];
    if (rawBanReason != null && rawBanReason is! String) {
      throw const FormatException('ban_reason must be a string or null');
    }
    final normalizedBanReason = rawBanReason is String
        ? rawBanReason.trim()
        : null;

    return UserStatus(
      isBanned: isBanned,
      banReason: normalizedBanReason == null || normalizedBanReason.isEmpty
          ? null
          : normalizedBanReason,
    );
  }

  final bool isBanned;
  final String? banReason;
}

class UserStatusService {
  UserStatusService({
    SupabaseClient? client,
    CurrentUserIdLoader? currentUserIdLoader,
    UserStatusRowLoader? rowLoader,
    Duration requestTimeout = const Duration(seconds: 7),
  }) : _client = client,
       _currentUserIdLoader = currentUserIdLoader,
       _rowLoader = rowLoader,
       _requestTimeout = requestTimeout;

  final SupabaseClient? _client;
  final CurrentUserIdLoader? _currentUserIdLoader;
  final UserStatusRowLoader? _rowLoader;
  final Duration _requestTimeout;

  Future<UserStatus>? _inFlightRequest;

  Future<UserStatus> fetchCurrentUserStatus() {
    final inFlightRequest = _inFlightRequest;
    if (inFlightRequest != null) return inFlightRequest;

    late final Future<UserStatus> request;
    request = _fetchCurrentUserStatus().whenComplete(() {
      if (identical(_inFlightRequest, request)) {
        _inFlightRequest = null;
      }
    });
    _inFlightRequest = request;
    return request;
  }

  Future<UserStatus> _fetchCurrentUserStatus() async {
    try {
      return await _loadCurrentUserStatus().timeout(_requestTimeout);
    } on TimeoutException {
      debugPrint(
        'User status request timed out; continuing in fail-open mode.',
      );
      return UserStatus.active;
    } catch (error) {
      debugPrint(
        'User status request failed; continuing in fail-open mode: $error',
      );
      return UserStatus.active;
    }
  }

  Future<UserStatus> _loadCurrentUserStatus() async {
    final userId =
        await (_currentUserIdLoader?.call() ??
            Future<String?>.value(
              (_client ?? Supabase.instance.client).auth.currentUser?.id,
            ));
    if (userId == null || userId.trim().isEmpty) {
      return UserStatus.active;
    }

    final row = await (_rowLoader?.call(userId) ?? _fetchUserStatusRow(userId));
    if (row == null) return UserStatus.active;
    return UserStatus.fromJson(row);
  }

  Future<Map<String, dynamic>?> _fetchUserStatusRow(String userId) async {
    final response = await (_client ?? Supabase.instance.client)
        .from('user_profiles')
        .select('is_banned, ban_reason')
        .eq('user_id', userId)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }
}
