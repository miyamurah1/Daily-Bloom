// Profile editor: edit display name + time zone, set notification
// preferences, then Save or Cancel. Presented as an [AlertDialog] by the
// caller (e.g. `showDialog(builder: (_) => ProfileEditor(...))`).
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../data/auth_store.dart';
import '../theme/sakura_theme.dart';

/// IANA time zone id -> human-readable label offered in the picker.
const Map<String, String> _timeZoneOptions = <String, String>{
  'UTC': 'Coordinated Universal Time',
  'America/New_York': 'Eastern Time (US & Canada)',
  'America/Chicago': 'Central Time (US & Canada)',
  'America/Denver': 'Mountain Time (US & Canada)',
  'America/Los_Angeles': 'Pacific Time (US & Canada)',
  'America/Sao_Paulo': 'Sao Paulo',
  'Europe/London': 'London',
  'Europe/Berlin': 'Paris / Berlin',
  'Asia/Kolkata': 'Kolkata',
  'Asia/Shanghai': 'Shanghai',
  'Asia/Tokyo': 'Tokyo',
  'Australia/Sydney': 'Sydney',
};

/// Profile editor: edit display name + time zone, toggle notification
/// preferences, then Save or Cancel.
class ProfileEditor extends StatefulWidget {
  final AuthUser user;
  final VoidCallback onSaved;

  const ProfileEditor({
    super.key,
    required this.user,
    required this.onSaved,
  });

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _tzCtrl;
  bool _saving = false;
  bool _notificationsEnabled = true;
  bool _dailyReminder = true;
  String _selectedTimezone = 'UTC';

  String get _initial {
    final source = widget.user.displayName.isNotEmpty
        ? widget.user.displayName
        : (widget.user.email.isNotEmpty ? widget.user.email : 'U');
    return source.substring(0, 1).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.displayName);
    _tzCtrl = TextEditingController(text: _selectedTimezone);
    _loadLocalTimezone();
  }

  Future<void> _loadLocalTimezone() async {
    try {
      final tz = await FlutterTimezone.getLocalTimezone();
      if (!mounted) return;
      setState(() {
        _selectedTimezone = tz.identifier;
        _tzCtrl.text = tz.identifier;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedTimezone = 'UTC';
        _tzCtrl.text = 'UTC';
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tzCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a display name.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      widget.onSaved();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTimeZone() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Time zone'),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: _timeZoneOptions.entries.map((e) {
              final id = e.key;
              final label = e.value;
              final selected = id == _selectedTimezone;
              return ListTile(
                leading: const Icon(Icons.access_time, size: 20),
                title: Text(label),
                subtitle: Text(id),
                trailing: selected
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop(id),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked != null && picked != _selectedTimezone && mounted) {
      setState(() {
        _selectedTimezone = picked;
        _tzCtrl.text = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SakuraColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      title: _buildHeader(),
      content: _buildBody(),
      actions: _buildFooter(),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: SakuraColors.primary,
          child: Text(
            _initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Edit profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: SakuraColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.user.email,
                style: TextStyle(
                  fontSize: 14,
                  color: SakuraColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'e.g. Alex',
              border: UnderlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Time zone'),
            subtitle: Text(
              _tzCtrl.text.isEmpty ? 'Not set' : _tzCtrl.text,
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _pickTimeZone,
          ),
          const Divider(height: 1),
          const SizedBox(height: 20),
          const Text(
            'Notifications',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Allow notifications'),
            subtitle: const Text(
              'Receive daily bloom and reminder alerts.',
            ),
            value: _notificationsEnabled,
            onChanged: _saving
                ? null
                : (value) =>
                    setState(() => _notificationsEnabled = value),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            title: const Text('Daily reminder'),
            subtitle: const Text(
              'Nudge you at your usual bloom time.',
            ),
            value: _dailyReminder,
            onChanged: _notificationsEnabled && !_saving
                ? (value) => setState(() => _dailyReminder = value ?? false)
                : null,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFooter() {
    return [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save changes'),
      ),
    ];
  }
}
