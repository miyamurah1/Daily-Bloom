import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../theme/sakura_theme.dart';
import '../widgets/motion.dart';
import '../widgets/theme_card.dart';

/// Theme Store — live catalog: buy with earned tokens, equip to re-skin
/// the whole app instantly. Offline it previews the catalog with buys and
/// equips disabled (never presented as purchasable).
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final _api = BloomApi();
  StoreState? _store;
  bool _loading = true;
  bool _offline = false;
  String? _busyId;

  static const _fallback = [
    StoreTheme(id: 'edo', name: 'Edo Period', label: 'CLASSIC', price: 0, owned: true),
    StoreTheme(id: 'midnight', name: 'Midnight Tokyo', label: 'MODERN', price: 0, owned: true),
    StoreTheme(id: 'kyoto', name: 'Kyoto Garden', label: 'NATURE', price: 500),
    StoreTheme(id: 'ocean', name: 'Kamogawa Blue', label: 'OCEAN', price: 650),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = await _api.fetchStore();
      if (!mounted) return;
      setState(() {
        _store = store;
        _loading = false;
        _offline = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      // Trust rule: offline previews the catalog honestly — buys and
      // equips stay disabled until the API is reachable.
      setState(() {
        _loading = false;
        _offline = true;
      });
    }
  }

  Future<void> _buy(StoreTheme t) async {
    if (_offline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Offline — connect to buy themes.')),
        );
      }
      return;
    }
    setState(() => _busyId = t.id);
    try {
      await _api.buyTheme(t.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.name} is yours — tap Equip to wear it.')),
        );
      }
    } catch (e) {
      if (e is AuthExpiredException || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is AuthException
                ? e.message
                : 'Buy failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _equip(StoreTheme t) async {
    if (_offline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Offline — connect to equip themes.')),
        );
      }
      return;
    }
    setState(() => _busyId = t.id);
    try {
      await ThemeStore.instance.equip(() => _api.equipTheme(t.id), t.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wearing ${t.name}.')),
        );
      }
    } catch (e) {
      if (e is AuthExpiredException || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not equip theme.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Preview a skin for a few seconds without equipping it.
  void _preview(StoreTheme t) {
    const seconds = 5;
    ThemeStore.instance
        .preview(t.id, duration: const Duration(seconds: seconds));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Previewing ${t.name} — reverts in ${seconds}s'),
        duration: const Duration(seconds: seconds),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;    final themes = store?.themes.isNotEmpty == true ? store!.themes : _fallback;
    // Offline the wallet is unknown — a guess here would be someone
    // else's number. Live balance comes from the server.
    final balanceLabel = _offline ? '–' : '${store?.balance ?? 450}';
    final active = store?.active ?? ThemeStore.instance.themeId;

    return Scaffold(
      backgroundColor: SakuraColors.background,
      appBar: AppBar(
        backgroundColor: SakuraColors.background,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SakuraColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: SakuraColors.cardBorder),
            ),
            child: Tooltip(
              message: 'Back',
              child: Icon(LucideIcons.arrowLeft,
                  size: 18, color: SakuraColors.ink),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '店舗',
              style: TextStyle(
                fontSize: 26,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: SakuraColors.primary,
                letterSpacing: 3.2,
              ),
            ),
            Text(
              'THEME STORE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 3.2,
                fontWeight: FontWeight.w600,
                color: SakuraColors.inkFaint,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 20, top: 12, bottom: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: SakuraColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SakuraColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.diamond,
                    size: 11, color: SakuraColors.primary),
                const SizedBox(width: 5),
                Text(balanceLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SakuraColors.primary,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ])),
              ],
            ),
          ),
        ],
      ),
      body: Entrance(
          delayMs: 80,
          child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: themes.length + (_offline ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (_offline && i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(LucideIcons.cloudOff,
                              size: 13, color: SakuraColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Offline — connect to buy or equip themes.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: SakuraColors.inkSoft),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final ti = _offline ? i - 1 : i;
                  final t = themes[ti];
                  final isActive = t.id == active;
                  final busy = _busyId == t.id;
                  return Padding(
                    padding: EdgeInsets.only(
                        bottom: ti == themes.length - 1 ? 0 : 16),
                    child: ThemeCard(
                      theme: t,
                      isActive: isActive,
                      isBusy: busy,
                      onPreview: () => _preview(t),
                      onAction: () {
                        if (t.owned) {
                          _equip(t);
                        } else {
                          _buy(t);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            ),
    );
  }
}
