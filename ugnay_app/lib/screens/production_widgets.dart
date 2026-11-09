import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../production_api.dart';

String kindLabel(String kind) => kind == 'HALF_NATIVE' ? 'Half Native' : 'Native';

Color statusColor(String status) {
  switch (status) {
    case 'OPEN':
      return Colors.blue.shade700;
    case 'AWARDED':
    case 'ACCEPTED':
      return Colors.green.shade700;
    case 'REJECTED':
      return Colors.red.shade700;
    case 'SUBMITTED':
      return Colors.orange.shade800;
    default:
      return Colors.grey.shade600;
  }
}

class StatusChip extends StatelessWidget {
  final String status;

  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c),
      ),
      child: Text(
        status == 'SUBMITTED' ? 'PENDING' : status,
        style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }
}

Future<void> showMessageDialog(BuildContext context, String title, String message) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorRetry({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

void showPhotoZoom(BuildContext context, String url) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(8),
      child: InteractiveViewer(child: Image.network(url)),
    ),
  );
}

/// Asks camera or gallery, then returns the picked photos as bytes (compressed to
/// 1600 px so they stay under the server's 5 MB limit). Returns [] if cancelled.
Future<List<Uint8List>> pickPhotos(BuildContext context, {required int maxCount}) async {
  if (maxCount <= 0) return [];
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return [];

  final picker = ImagePicker();
  if (source == ImageSource.camera) {
    final f = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
    return f == null ? [] : [await f.readAsBytes()];
  }
  final files = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85);
  final out = <Uint8List>[];
  for (final f in files.take(maxCount)) {
    out.add(await f.readAsBytes());
  }
  return out;
}

/// Create or edit a supplier. Returns a map with name, phone, address, notes, is_active.
class SupplierDialog extends StatefulWidget {
  final Supplier? supplier;

  const SupplierDialog({super.key, this.supplier});

  @override
  State<SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.supplier?.address ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.supplier?.notes ?? '');
  late bool _active = widget.supplier?.isActive ?? true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.supplier != null;
    return AlertDialog(
      title: Text(editing ? 'Edit supplier' : 'New supplier'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Min 2 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
              ),
              if (editing)
                SwitchListTile(
                  title: const Text('Active'),
                  subtitle: const Text('Inactive suppliers are hidden when adding entries',
                      style: TextStyle(fontSize: 12)),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'phone': _phone.text.trim(),
                'address': _address.text.trim(),
                'notes': _notes.text.trim(),
                'is_active': _active,
              });
            }
          },
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}