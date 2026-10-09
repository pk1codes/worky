import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import 'chrome.dart';
import 'langs.dart';
import 'session.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, dynamic>> _rows = [];
  final Map<String, TextEditingController> _names = {
    for (final code in kLangs) code: TextEditingController(),
  };
  final TextEditingController _parent = TextEditingController();
  String? _coverId;
  var _kind = 'parent';
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _names.values) {
      controller.dispose();
    }
    _parent.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await SessionHost.of(context).api.adminCategories();
      if (mounted) setState(() => _rows = rows);
    } catch (_) {}
  }

  Future<void> _save() async {
    final session = SessionHost.of(context);
    if (_coverId == null) {
      await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
      return;
    }
    setState(() => _busy = true);
    try {
      await session.api.saveCategory(
        parentId: _parent.text.trim(),
        kind: _kind,
        names: {for (final code in kLangs) code: _names[code]!.text.trim()},
        coverMediaId: _coverId!,
        sort: _rows.length,
      );
      for (final controller in _names.values) {
        controller.clear();
      }
      _coverId = null;
      await _load();
    } catch (_) {
      if (mounted) await Speaker.say(session.lang, AppLocalizations.of(context).tryAgain);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Paged(
      page: 8,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              BigIcon(icon: Icons.arrow_back, label: l10n.back, onTap: () => Navigator.pop(context)),
              Text(l10n.admin, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              TextField(
                controller: _parent,
                decoration: InputDecoration(labelText: l10n.nameLabel),
              ),
              for (final code in kLangs)
                TextField(
                  controller: _names[code],
                  decoration: InputDecoration(labelText: '${kAutonym[code]} · ${l10n.nameLabel}'),
                ),
              Row(
                children: [
                  BigIcon(
                    icon: Icons.folder,
                    label: 'Parent',
                    filled: _kind == 'parent',
                    onTap: () => setState(() => _kind = 'parent'),
                  ),
                  BigIcon(
                    icon: Icons.badge,
                    label: 'Job',
                    filled: _kind == 'job',
                    onTap: () => setState(() => _kind = 'job'),
                  ),
                ],
              ),
              Row(
                children: [
                  BigIcon(
                    icon: Icons.photo_camera,
                    label: l10n.addPhoto,
                    onTap: () async {
                      final api = SessionHost.of(context).api;
                      final file = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1600,
                        imageQuality: 80,
                      );
                      if (file == null || !mounted) return;
                      final id = await api.upload('image', await file.readAsBytes(), 'image/jpeg');
                      if (!mounted) return;
                      setState(() => _coverId = id);
                    },
                  ),
                  BigIcon(icon: Icons.save, label: l10n.save, filled: true, onTap: _busy ? null : _save),
                ],
              ),
              for (final row in _rows)
                ListTile(
                  leading: row['coverUrl'] == null
                      ? null
                      : Image.network('${row['coverUrl']}', width: 48, height: 48, fit: BoxFit.cover),
                  title: Text('${(row['names'] as Map?)?['en'] ?? row['id']}'),
                  subtitle: Text('${row['kind'] ?? ''} ${row['parentId'] ?? ''}'),
                  trailing: IconButton(
                    icon: Icon(row['active'] == false ? Icons.visibility : Icons.visibility_off),
                    tooltip: row['active'] == false ? l10n.show : l10n.hide,
                    onPressed: () async {
                      await SessionHost.of(context).api.hideCategory(
                            row['id'] as String,
                            active: row['active'] == false,
                          );
                      await _load();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
