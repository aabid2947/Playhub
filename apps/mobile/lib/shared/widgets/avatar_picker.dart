import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

/// Circle avatar with built-in pick + upload. Shows current image (or
/// initials fallback), spinner while uploading, error overlay on failure.
class AvatarPicker extends ConsumerStatefulWidget {
  const AvatarPicker({
    required this.entity,
    required this.url,
    required this.onUploaded,
    this.fallbackInitials = '',
    this.radius = 36,
    super.key,
  });

  final String entity; // 'students' | 'coaches' | 'academy'
  final String? url;
  final ValueChanged<String> onUploaded;
  final String fallbackInitials;
  final double radius;

  @override
  ConsumerState<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends ConsumerState<AvatarPicker> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final profile = await ref.read(currentProfileProvider.future);
    final academyId = profile?.academyId;
    if (academyId == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await ref.read(storageServiceProvider).pickAndUploadAvatar(
            academyId: academyId,
            entity: widget.entity,
          );
      if (url != null) {
        widget.onUploaded(url);
      }
    } on Object catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    final url = widget.url;
    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: r,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              child: url == null || url.isEmpty
                  ? Text(
                      widget.fallbackInitials.isEmpty
                          ? '?'
                          : widget.fallbackInitials.toUpperCase(),
                      style: TextStyle(fontSize: r * 0.7),
                    )
                  : ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: url,
                        width: r * 2,
                        height: r * 2,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Material(
                color: Theme.of(context).colorScheme.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _busy ? null : _pick,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.edit, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(color: Colors.red, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

/// Read-only circular avatar (no edit affordance). Used in lists.
class AvatarView extends StatelessWidget {
  const AvatarView({
    required this.url,
    required this.fallbackInitials,
    this.radius = 20,
    super.key,
  });

  final String? url;
  final String fallbackInitials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        child: Text(
          fallbackInitials.isEmpty ? '?' : fallbackInitials.toUpperCase(),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor:
          Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (_, __) => const Padding(
            padding: EdgeInsets.all(4),
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          errorWidget: (_, __, ___) => Text(
            fallbackInitials.isEmpty ? '?' : fallbackInitials.toUpperCase(),
          ),
        ),
      ),
    );
  }
}
