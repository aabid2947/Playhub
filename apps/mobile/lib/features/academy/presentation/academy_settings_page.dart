import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/academy/data/academy.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';

class AcademySettingsPage extends ConsumerStatefulWidget {
  const AcademySettingsPage({super.key});

  @override
  ConsumerState<AcademySettingsPage> createState() =>
      _AcademySettingsPageState();
}

class _AcademySettingsPageState extends ConsumerState<AcademySettingsPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _website = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _isError = false;
  Academy? _loaded;
  String? _logo;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _website.dispose();
    super.dispose();
  }

  void _hydrate(Academy a) {
    if (_loaded?.id == a.id) return;
    _loaded = a;
    _name.text = a.name;
    _email.text = a.email ?? '';
    _phone.text = a.phone ?? '';
    _address.text = a.address ?? '';
    _city.text = a.city ?? '';
    _website.text = a.website ?? '';
    _logo = a.logo;
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
      _isError = false;
    });
    try {
      await updateMyAcademy(ref, {
        'name': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'website': _website.text.trim().isEmpty ? null : _website.text.trim(),
        'logo': _logo,
      });
      setState(() => _message = 'Saved');
    } on Object catch (e) {
      setState(() {
        _message = e.toString();
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final academyAsync = ref.watch(myAcademyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Academy settings')),
      body: academyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (academy) {
          if (academy == null) {
            return const Center(child: Text('No academy found.'));
          }
          _hydrate(academy);
          final initials = _name.text.isNotEmpty ? _name.text[0] : 'A';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: AvatarPicker(
                    entity: 'academy',
                    url: _logo,
                    fallbackInitials: initials,
                    onUploaded: (url) => setState(() => _logo = url),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _city,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _website,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Website'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _isError ? Colors.red : Colors.green,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
