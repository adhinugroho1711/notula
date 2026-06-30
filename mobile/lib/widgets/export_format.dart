import 'package:flutter/material.dart';

import '../services/export_service.dart';

/// Dialog pilih format ekspor (TXT / Markdown / PDF). Null bila dibatalkan.
Future<ExportFormat?> showExportFormatPicker(BuildContext context) {
  return showDialog<ExportFormat>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Ekspor sebagai'),
      children: [
        for (final f in ExportFormat.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, f),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(switch (f) {
                    ExportFormat.txt => Icons.description_outlined,
                    ExportFormat.markdown => Icons.code_rounded,
                    ExportFormat.pdf => Icons.picture_as_pdf_outlined,
                  }, size: 20),
                  const SizedBox(width: 12),
                  Text(f.label, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
