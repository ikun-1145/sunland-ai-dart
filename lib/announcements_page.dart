import 'package:flutter/material.dart';

import 'announcement_service.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key, this.service});

  final AnnouncementService? service;

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late final AnnouncementService _service =
      widget.service ?? AnnouncementService();
  late Future<List<PublicAnnouncement>> _future = _service.load();

  @override
  void dispose() {
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _service.load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('公告')),
      body: FutureBuilder<List<PublicAnnouncement>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _FeedbackState(
              icon: Icons.cloud_off_outlined,
              message: '公告暂时无法加载，请稍后重试。',
              actionLabel: '重试',
              onPressed: _reload,
            );
          }
          final announcements = snapshot.data ?? const <PublicAnnouncement>[];
          if (announcements.isEmpty) {
            return _FeedbackState(
              icon: Icons.campaign_outlined,
              message: '当前没有有效公告。',
              actionLabel: '刷新',
              onPressed: _reload,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: announcements.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _AnnouncementCard(
                announcement: announcements[index],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});

  final PublicAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(announcement.title, style: theme.textTheme.titleMedium),
            if (announcement.publishedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                '发布时间：${announcement.publishedAt!.toLocal().toString().substring(0, 16)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Text(announcement.content),
          ],
        ),
      ),
    );
  }
}

class _FeedbackState extends StatelessWidget {
  const _FeedbackState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
