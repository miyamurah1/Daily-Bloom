// Profile editor: edit display name + time zone, set notification
// preferences, then Save or Cancel. Presented as an [AlertDialog] by the
// caller (e.g. `showDialog(builder: (_) => ProfileEditor(...))`).
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../data/auth_store.dart';
import '../data/haptics.dart';
import '../data/reminders.dart';
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

/// Validated profile-editor result handed to [ProfileEditor.onSave].
class ProfileSave {
  final String displayName;
  final String timezone;
  final bool notificationsEnabled;
  final bool dailyReminder;

  final int dailyReminderHour;

  const ProfileSave({
    required this.displayName,
    required this.timezone,
    required this.notificationsEnabled,
    required this.dailyReminder,
    required this.dailyReminderHour,
  });
}

/// Profile editor: edit display name + time zone, toggle notification
/// preferences, then Save or Cancel.
///
/// [onSave] receives the validated result so the caller owns persistence.
class ProfileEditor extends StatefulWidget {
  final AuthUser user;
  final int dailyReminderHour;
  final Future<void> Function(ProfileSave result) onSave;

  const ProfileEditor({
    super.key,
    required this.user,
    required this.dailyReminderHour,
    required this.onSave,
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
  int _dailyReminderHour = 0;
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
    _notificationsEnabled = ReminderService.instance.enabled;
    _dailyReminder = ReminderService.instance.weeklyEnabled;
    _dailyReminderHour = widget.dailyReminderHour;
    _tzCtrl = TextEditingController(text: _selectedTimezone);
    _loadLocalTimezone();
  }

  Future<void> _pickReminderHour() async {
    final initialTime = TimeOfDay(hour: _dailyReminderHour, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: SakuraColors.primary,
                  onPrimary: SakuraColors.inkFaint,
                  surface: SakuraColors.surface,
                  onSurface: SakuraColors.ink,
                ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: SakuraColors.primary),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      AppHaptics.tap();
      final hour = picked.hour.clamp(0, 23);
      setState(() => _dailyReminderHour = hour);
    }
  }

  Future<void> _loadLocalTimezone() async {
    final stored = ReminderService.instance.timezoneOverride;
    if (stored != null && stored.isNotEmpty && mounted) {
      setState(() {
        _selectedTimezone = stored;
        _tzCtrl.text = stored;
      });
      return;
    }
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
    if (name.length < 2 || name.length > 40) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Display name must be 2-40 characters.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    AppHaptics.tap();
    try {
      await widget.onSave(ProfileSave(
        displayName: name,
        timezone: _selectedTimezone,
        notificationsEnabled: _notificationsEnabled,
        dailyReminder: _notificationsEnabled && _dailyReminder,
        dailyReminderHour: _dailyReminderHour,
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save profile - try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
              fontSize: 13,
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
            title: const Text('Daily nudge'),
            subtitle: const Text(
              'One gentle reminder at a set hour.',
            ),
            value: _notificationsEnabled,
            onChanged: _saving
                ? null
                : (value) {
                    AppHaptics.tap();
                    setState(() => _notificationsEnabled = value);
                  },
            controlAffinity: ListTileControlAffinity.leading,
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Daily reminder hour'),
            subtitle: Text(
              '$_dailyReminderHour:00',
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _pickReminderHour,
          ),
          CheckboxListTile(
            title: const Text('Sunday review'),
            subtitle: const Text(
              'A calm weekly look-back every Sunday evening.',
            ),
            value: _dailyReminder,
            onChanged: _notificationsEnabled && !_saving
                ? (value) {
                    AppHaptics.tap();
                    setState(() => _dailyReminder = value ?? false);
                  }
                : null,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFooter() {
    final saving = _saving ? const SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ) : null;
    final saveLabel = saving ?? const Text('Save changes');
    return [
      TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(88, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        onPressed: _saving ? null : _save,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          child: saveLabel,
        ),
      ),
    ];
  }
}
