import 'dart:io';

import 'package:chopper/chopper.dart' show HttpMethod;
import 'package:file_picker/file_picker.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:provider/provider.dart';
import 'package:waterflyiii/auth.dart';
import 'package:waterflyiii/generated/l10n/app_localizations.dart';
import 'package:waterflyiii/generated/swagger_fireflyiii_api/firefly_iii.swagger.dart';
import 'package:waterflyiii/services/gemini_service.dart';
import 'package:waterflyiii/settings.dart';

class SimpleAttachmentsDialog extends StatefulWidget {
  const SimpleAttachmentsDialog({
    super.key,
    required this.attachments,
    required this.transactionId,
    this.onTransactionDataParsed,
  });

  final List<AttachmentRead> attachments;
  final String? transactionId;
  final void Function(TransactionData)? onTransactionDataParsed;

  @override
  State<SimpleAttachmentsDialog> createState() =>
      _SimpleAttachmentsDialogState();
}

class _SimpleAttachmentsDialogState extends State<SimpleAttachmentsDialog> {
  final Logger log = Logger("Pages.Transaction.SimpleAttachmentsDialog");

  // HTTP client for downloads
  static final http.Client httpClient = http.Client();

  bool _isImageAttachment(AttachmentRead attachment) {
    final String filename = attachment.attributes.filename.toLowerCase();
    return filename.endsWith('.jpg') ||
        filename.endsWith('.jpeg') ||
        filename.endsWith('.png') ||
        filename.endsWith('.gif') ||
        filename.endsWith('.bmp') ||
        filename.endsWith('.webp');
  }

  /// Get authentication headers for API requests
  Future<Map<String, String>> _getAuthHeaders() async {
    final AuthUser? user = context.read<FireflyService>().user;
    return user?.headers() ?? {};
  }

  /// Download attachment image to temporary storage for preview
  Future<File?> _downloadImageToTemp(AttachmentRead attachment) async {
    try {
      final AuthUser? user = context.read<FireflyService>().user;
      if (user == null || attachment.attributes.downloadUrl == null) {
        return null;
      }

      // Create a cache key based on attachment ID and last modified date
      final String cacheKey =
          '${attachment.id}_${attachment.attributes.updatedAt?.millisecondsSinceEpoch ?? attachment.attributes.createdAt?.millisecondsSinceEpoch ?? 0}';
      final Directory tmpDir = await getTemporaryDirectory();
      final File cachedFile =
          File('${tmpDir.path}/attachment_preview_$cacheKey.jpg');

      // Return cached file if it exists and is recent (less than 1 hour old)
      if (await cachedFile.exists()) {
        final DateTime lastModified = await cachedFile.lastModified();
        final Duration age = DateTime.now().difference(lastModified);
        if (age.inHours < 1) {
          return cachedFile;
        }
      }

      // Download the image
      final http.Request request = http.Request(
        HttpMethod.Get,
        Uri.parse(attachment.attributes.downloadUrl!),
      );
      request.headers.addAll(user.headers());

      final http.StreamedResponse resp = await httpClient.send(request);
      if (resp.statusCode != 200) {
        log.warning("Failed to download image for preview: ${resp.statusCode}");
        return null;
      }

      // Save to cache
      final List<int> fileData = [];
      await for (List<int> chunk in resp.stream) {
        fileData.addAll(chunk);
      }

      await cachedFile.writeAsBytes(fileData);
      return cachedFile;
    } catch (e, stackTrace) {
      log.severe("Error downloading image to temp", e, stackTrace);
      return null;
    }
  }

  Widget _buildImageErrorWidget() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 48),
            SizedBox(height: 8),
            Text('Failed to load image'),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(AttachmentRead attachment) {
    if (widget.transactionId == null) {
      // For new transactions, use local file path
      final String? localPath = attachment.attributes.uploadUrl;
      if (localPath != null && File(localPath).existsSync()) {
        return Image.file(
          File(localPath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildImageErrorWidget();
          },
        );
      }
    }

    // For existing transactions, load from server
    final String? downloadUrl = attachment.attributes.downloadUrl;
    if (downloadUrl == null) {
      return _buildImageErrorWidget();
    }

    return FutureBuilder<Map<String, String>>(
      future: _getAuthHeaders(),
      builder: (context, headerSnapshot) {
        if (headerSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!headerSnapshot.hasData) {
          return _buildImageErrorWidget();
        }

        // Try network image first
        return Image.network(
          downloadUrl,
          fit: BoxFit.cover,
          headers: headerSnapshot.data,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            // If network fails, try downloading to temp storage
            return FutureBuilder<File?>(
              future: _downloadImageToTemp(attachment),
              builder: (context, fileSnapshot) {
                if (fileSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (fileSnapshot.hasData && fileSnapshot.data != null) {
                  return Image.file(
                    fileSnapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildImageErrorWidget();
                    },
                  );
                } else {
                  return _buildImageErrorWidget();
                }
              },
            );
          },
        );
      },
    );
  }

  void _parseImageWithAI(AttachmentRead attachment) async {
    final SettingsProvider settings = context.read<SettingsProvider>();
    final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);

    // Check if Gemini API is configured
    if (settings.geminiApiKey == null || settings.geminiApiKey!.isEmpty) {
      msg.showSnackBar(
        SnackBar(
          content: const Text('Please configure Gemini AI in settings first'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              Navigator.of(context).pushNamed('/settings/gemini');
            },
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Show loading dialog
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Parsing receipt with AI...')),
            ],
          ),
        ),
      );
    }

    try {
      // Get the image file (either local or download from server)
      File? imageFile;

      if (widget.transactionId == null) {
        // For new transactions, use local file path
        final String? localPath = attachment.attributes.uploadUrl;
        if (localPath != null && File(localPath).existsSync()) {
          imageFile = File(localPath);
        }
      } else {
        // For existing transactions, download the image
        imageFile = await _downloadImageToTemp(attachment);
      }

      if (imageFile == null || !await imageFile.exists()) {
        // Close loading dialog
        if (context.mounted) {
          Navigator.of(context).pop();
        }
        msg.showSnackBar(
          const SnackBar(
            content: Text('Could not access image file for parsing'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Parse with Gemini
      final GeminiService geminiService = GeminiService(
        apiKey: settings.geminiApiKey!,
        model: settings.geminiModel,
        language: settings.geminiLanguage,
      );

      final TransactionData? transactionData =
          await geminiService.parseReceipt(imageFile);

      // Close loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (transactionData == null) {
        msg.showSnackBar(
          const SnackBar(
            content: Text('Could not extract transaction data from receipt'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Show parsed data dialog
      if (context.mounted) {
        print(
            'SimpleAttachmentsDialog: About to show ReceiptParseResultDialog with callback: ${widget.onTransactionDataParsed != null}');
        showDialog(
          context: context,
          builder: (context) => ReceiptParseResultDialog(
            transactionData: transactionData,
            onUseData: widget.onTransactionDataParsed,
          ),
        );
      }
    } catch (e) {
      log.severe("Error parsing receipt with AI", e);

      // Close loading dialog if still open
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      msg.showSnackBar(
        SnackBar(
          content: Text('Error parsing receipt: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _viewImage(AttachmentRead attachment) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(attachment.attributes.filename),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              child: _buildImagePreview(attachment),
            ),
          ),
        ),
      ),
    );
  }

  void _deleteAttachment(int index) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attachment'),
        content: const Text('Are you sure you want to delete this attachment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        widget.attachments.removeAt(index);
      });
    }
  }

  void _addFromCamera() async {
    final ImagePicker picker = ImagePicker();
    final XFile? imageFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (imageFile == null) return;

    // Create a fake attachment for demo
    final AttachmentRead newAttachment = AttachmentRead(
      type: "attachments",
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      attributes: Attachment(
        attachableType: AttachableType.transactionjournal,
        attachableId: widget.transactionId ?? "new",
        filename: imageFile.name,
        uploadUrl: imageFile.path,
        size: await imageFile.length(),
        createdAt: DateTime.now(),
      ),
      links: const ObjectLink(),
    );

    setState(() {
      widget.attachments.add(newAttachment);
    });
  }

  void _addFromFiles() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final PlatformFile file = result.files.first;
    if (file.path == null) return;

    // Create a fake attachment for demo
    final AttachmentRead newAttachment = AttachmentRead(
      type: "attachments",
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      attributes: Attachment(
        attachableType: AttachableType.transactionjournal,
        attachableId: widget.transactionId ?? "new",
        filename: file.name,
        uploadUrl: file.path,
        size: file.size,
        createdAt: DateTime.now(),
      ),
      links: const ObjectLink(),
    );

    setState(() {
      widget.attachments.add(newAttachment);
    });
  }

  void _downloadAttachment(AttachmentRead attachment) async {
    final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
    final AuthUser? user = context.read<FireflyService>().user;
    final S l10n = S.of(context);

    if (user == null) {
      log.severe("downloadAttachment: user was null");
      msg.showSnackBar(
        SnackBar(
          content: Text(l10n.errorAPIUnavailable),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (attachment.attributes.downloadUrl == null) {
      msg.showSnackBar(
        const SnackBar(
          content: Text('Download URL not available'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final Directory tmpPath = await getTemporaryDirectory();
      final String filePath =
          "${tmpPath.path}/${attachment.attributes.filename}";

      // Show download started message
      msg.showSnackBar(
        SnackBar(
          content: Text('Downloading ${attachment.attributes.filename}...'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final http.Request request = http.Request(
        HttpMethod.Get,
        Uri.parse(attachment.attributes.downloadUrl!),
      );
      request.headers.addAll(user.headers());

      final http.StreamedResponse resp = await httpClient.send(request);
      if (resp.statusCode != 200) {
        log.warning("got invalid status code ${resp.statusCode}");
        msg.showSnackBar(
          SnackBar(
            content: Text(l10n.transactionDialogAttachmentsErrorDownload),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Collect file data
      final List<int> fileData = <int>[];
      await for (List<int> chunk in resp.stream) {
        fileData.addAll(chunk);
      }

      // Write file
      await File(filePath).writeAsBytes(fileData, flush: true);

      // Open file
      final OpenResult file = await OpenFile.open(filePath);
      if (file.type != ResultType.done) {
        log.severe("error opening file", file.message);
        msg.showSnackBar(
          SnackBar(
            content: Text(
              l10n.transactionDialogAttachmentsErrorOpen(file.message),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        msg.showSnackBar(
          SnackBar(
            content: Text('Downloaded ${attachment.attributes.filename}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      log.severe("download error", e, stackTrace);
      msg.showSnackBar(
        SnackBar(
          content: Text(l10n.transactionDialogAttachmentsErrorDownload),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(S.of(context).transactionDialogAttachmentsTitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
        body: widget.attachments.isEmpty
            ? _buildEmptyState()
            : _buildAttachmentsList(),
        bottomNavigationBar: _buildActionButtons(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.attach_file,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No Attachments',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Add photos or files to this transaction',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.attachments.length,
      itemBuilder: (context, index) {
        final attachment = widget.attachments[index];
        final isImage = _isImageAttachment(attachment);

        String subtitle = "";
        final DateTime? modDate =
            attachment.attributes.updatedAt ?? attachment.attributes.createdAt;
        if (modDate != null) {
          subtitle = DateFormat.yMd().add_Hms().format(modDate.toLocal());
        }
        if (attachment.attributes.size != null) {
          subtitle = "$subtitle (${filesize(attachment.attributes.size)})";
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              // Image preview for images
              if (isImage)
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: _buildImagePreview(attachment),
                  ),
                ),

              // File info and actions
              ListTile(
                leading: Icon(isImage ? Icons.image : Icons.attach_file),
                title: Text(
                  attachment.attributes.title ?? attachment.attributes.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Parse with AI button (only for images)
                    if (isImage)
                      IconButton(
                        icon: const Icon(Icons.auto_awesome),
                        tooltip: 'Parse with AI',
                        onPressed: () => _parseImageWithAI(attachment),
                      ),
                    // View button (only for images)
                    if (isImage)
                      IconButton(
                        icon: const Icon(Icons.visibility),
                        tooltip: 'View',
                        onPressed: () => _viewImage(attachment),
                      ),
                    // Download button (for all files)
                    if (!isImage)
                      IconButton(
                        icon: const Icon(Icons.download),
                        tooltip: 'Download',
                        onPressed: () => _downloadAttachment(attachment),
                      ),
                    // Delete button
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: 'Delete',
                      onPressed: () => _deleteAttachment(index),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addFromCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addFromFiles,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReceiptParseResultDialog extends StatelessWidget {
  final TransactionData transactionData;
  final VoidCallback? onSaveImage;
  final void Function(TransactionData)? onUseData;

  const ReceiptParseResultDialog({
    super.key,
    required this.transactionData,
    this.onSaveImage,
    this.onUseData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.smart_toy, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('AI Parsed Receipt Data'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            // Add helpful context at the top
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This data will be used to auto-fill the transaction form',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (transactionData.merchant != null) ...[
              Text('Merchant', style: theme.textTheme.labelMedium),
              Text(transactionData.merchant!, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
            ],
            if (transactionData.amount != null) ...[
              Text('Amount', style: theme.textTheme.labelMedium),
              Text(
                transactionData.currency != null
                    ? '${transactionData.currency} ${transactionData.amount!.toStringAsFixed(2)}'
                    : transactionData.amount!.toStringAsFixed(2),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
            ],
            if (transactionData.date != null) ...[
              Text('Date', style: theme.textTheme.labelMedium),
              Text(
                DateFormat.yMd().format(transactionData.date!),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
            ],
            if (transactionData.category != null) ...[
              Text('Category', style: theme.textTheme.labelMedium),
              Text(transactionData.category!, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
            ],
            if (transactionData.description != null) ...[
              Text('Description', style: theme.textTheme.labelMedium),
              Text(transactionData.description!,
                  style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
            ],
            if (transactionData.paymentMethod != null) ...[
              Text('Payment Method', style: theme.textTheme.labelMedium),
              Text(transactionData.paymentMethod!,
                  style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
            ],
            if (transactionData.notes != null) ...[
              Text('Notes', style: theme.textTheme.labelMedium),
              Text(transactionData.notes!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
        if (onSaveImage != null)
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();
              onSaveImage!();
            },
            child: const Text('Save Image'),
          ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            if (onUseData != null) {
              print(
                  'ReceiptParseResultDialog: Calling onUseData with: $transactionData');
              onUseData!(transactionData);
            } else {
              print(
                  'ReceiptParseResultDialog: onUseData is null, showing fallback message');
              _notifyTransactionData(context, transactionData);
            }
          },
          child: const Text('Auto-Fill Transaction Form'),
        ),
      ],
    );
  }

  void _notifyTransactionData(BuildContext context, TransactionData data) {
    // This would need to be implemented to pass the data back to the transaction form
    // For now, we'll just show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Feature coming soon: Auto-fill transaction form'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
