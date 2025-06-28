import 'dart:convert';
import 'dart:io';

import 'package:chopper/chopper.dart' show HttpMethod, Response;
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

class AttachmentDialog extends StatefulWidget {
  const AttachmentDialog({
    super.key,
    required this.attachments,
    required this.transactionId,
    this.onTransactionDataParsed,
  });

  final List<AttachmentRead> attachments;
  final String? transactionId;
  final void Function(TransactionData)? onTransactionDataParsed;

  /// Returns true if this is a new transaction (not yet saved)
  bool get isNewTransaction => transactionId == null;

  @override
  State<AttachmentDialog> createState() => _AttachmentDialogState();
}

class _AttachmentDialogState extends State<AttachmentDialog>
    with SingleTickerProviderStateMixin {
  final Logger log = Logger("Pages.Transaction.AttachmentDialog");

  final Map<int, double> _dlProgress = <int, double>{};

  void downloadAttachment(
    BuildContext context,
    AttachmentRead attachment,
    int i,
  ) async {
    final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
    final AuthUser? user = context.read<FireflyService>().user;
    final S l10n = S.of(context);
    late int total;
    int received = 0;
    final List<int> fileData = <int>[];

    if (user == null) {
      log.severe("downloadAttachment: user was null");
      throw Exception(l10n.errorAPIUnavailable);
    }

    final Directory tmpPath = await getTemporaryDirectory();
    final String filePath = "${tmpPath.path}/${attachment.attributes.filename}";

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
    total = resp.contentLength ?? 0;
    if (total == 0) {
      total = attachment.attributes.size ?? 0;
    }
    resp.stream.listen(
      (List<int> value) {
        setState(() {
          fileData.addAll(value);
          received += value.length;
          _dlProgress[i] = received / total;
          log.finest(
            () =>
                "received ${value.length} bytes (total $received of $total), ${received / total * 100}%",
          );
        });
      },
      cancelOnError: true,
      onDone: () async {
        setState(() {
          _dlProgress.remove(i);
        });
        log.finest(() => "writing ${fileData.length} bytes to $filePath");
        await File(filePath).writeAsBytes(fileData, flush: true);
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
        }
      },
      onError: (Object e, StackTrace s) {
        log.severe("download error", e, s);
        setState(() {
          _dlProgress.remove(i);
        });
        msg.showSnackBar(
          SnackBar(
            content: Text(l10n.transactionDialogAttachmentsErrorDownload),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void deleteAttachment(
    BuildContext context,
    AttachmentRead attachment,
    int i,
  ) async {
    final FireflyIii api = context.read<FireflyService>().api;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) =>
          const AttachmentDeletionConfirmDialog(),
    );
    if (ok == null || !ok) {
      return;
    }

    await api.v1AttachmentsIdDelete(id: attachment.id);
    setState(() {
      widget.attachments.removeAt(i);
    });
  }

  void uploadAttachment(BuildContext context, PlatformFile file) async {
    final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
    final FireflyIii api = context.read<FireflyService>().api;
    final AuthUser? user = context.read<FireflyService>().user;
    final S l10n = S.of(context);

    if (user == null) {
      log.severe("uploadAttachment: user was null");
      throw Exception(l10n.errorAPIUnavailable);
    }

    final Response<AttachmentSingle> respAttachment =
        await api.v1AttachmentsPost(
      body: AttachmentStore(
        filename: file.name,
        attachableType: AttachableType.transactionjournal,
        attachableId: widget.transactionId!,
      ),
    );
    if (!respAttachment.isSuccessful || respAttachment.body == null) {
      late String error;
      try {
        final ValidationErrorResponse valError =
            ValidationErrorResponse.fromJson(
          json.decode(respAttachment.error.toString()),
        );
        error = valError.message ?? l10n.errorUnknown;
      } catch (_) {
        error = l10n.errorUnknown;
      }
      msg.showSnackBar(
        SnackBar(
          content: Text(l10n.transactionDialogAttachmentsErrorUpload(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    AttachmentRead newAttachment = respAttachment.body!.data;
    final int newAttachmentIndex =
        widget.attachments.length; // Will be added later, no -1 needed.
    final int total = file.size;
    newAttachment = newAttachment.copyWith(
      attributes: newAttachment.attributes.copyWith(size: total),
    );
    int sent = 0;

    setState(() {
      widget.attachments.add(newAttachment);
      _dlProgress[newAttachmentIndex] = -0.0001;
    });

    final http.StreamedRequest request = http.StreamedRequest(
      HttpMethod.Post,
      Uri.parse(newAttachment.attributes.uploadUrl!),
    );
    request.headers.addAll(user.headers());
    request.headers[HttpHeaders.contentTypeHeader] =
        ContentType.binary.mimeType;
    log.fine(() => "AttachmentUpload: Starting Upload $newAttachmentIndex");
    request.contentLength = total;

    File(file.path!).openRead().listen(
      (List<int> data) {
        setState(() {
          sent += data.length;
          _dlProgress[newAttachmentIndex] = sent / total * -1;
          log.finest(
            () =>
                "sent ${data.length} bytes (total $sent of $total), ${sent / total * 100}%",
          );
        });
        request.sink.add(data);
      },
      onDone: () {
        request.sink.close();
      },
    );

    final http.StreamedResponse resp = await httpClient.send(request);
    log.fine(() => "AttachmentUpload: Done with Upload $newAttachmentIndex");
    setState(() {
      _dlProgress.remove(newAttachmentIndex);
    });
    if (resp.statusCode == HttpStatus.ok ||
        resp.statusCode == HttpStatus.created ||
        resp.statusCode == HttpStatus.noContent) {
      return;
    }
    late String error;
    try {
      final String respString = await resp.stream.bytesToString();
      final ValidationErrorResponse valError = ValidationErrorResponse.fromJson(
        json.decode(respString),
      );
      error = valError.message ?? l10n.errorUnknown;
    } catch (_) {
      error = l10n.errorUnknown;
    }
    msg.showSnackBar(
      SnackBar(
        content: Text(l10n.transactionDialogAttachmentsErrorUpload(error)),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await api.v1AttachmentsIdDelete(id: newAttachment.id);
    setState(() {
      widget.attachments.removeAt(newAttachmentIndex);
    });
  }

  void fakeDownloadAttachment(
    BuildContext context,
    AttachmentRead attachment,
  ) async {
    final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
    final S l10n = S.of(context);

    final OpenResult file = await OpenFile.open(
      attachment.attributes.uploadUrl,
    );
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
    }
  }

  void fakeDeleteAttachment(BuildContext context, int i) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) =>
          const AttachmentDeletionConfirmDialog(),
    );
    if (ok == null || !ok) {
      return;
    }
    setState(() {
      widget.attachments.removeAt(i);
    });
  }

  void fakeUploadAttachment(BuildContext context, PlatformFile file) async {
    final AttachmentRead newAttachment = AttachmentRead(
      type: "attachments",
      id: widget.attachments.length.toString(),
      attributes: Attachment(
        attachableType: AttachableType.transactionjournal,
        attachableId: "FAKE",
        filename: file.name,
        uploadUrl: file.path,
        size: file.size,
      ),
      links: const ObjectLink(),
    );
    setState(() {
      widget.attachments.add(newAttachment);
    });
  }

  bool _isImageAttachment(AttachmentRead attachment) {
    final String filename = attachment.attributes.filename.toLowerCase();
    return filename.endsWith('.jpg') ||
        filename.endsWith('.jpeg') ||
        filename.endsWith('.png') ||
        filename.endsWith('.gif') ||
        filename.endsWith('.bmp') ||
        filename.endsWith('.webp');
  }

  /// Get authenticated image widget for an attachment
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
      return _buildImageErrorWidget();
    }

    // For existing transactions, try direct network access first, then fallback to download
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

  Widget _buildImageErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image,
              color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text('Failed to load image',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

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
    } catch (e) {
      log.warning("Error downloading image to temp: $e");
      return null;
    }
  }

  void parseReceiptAttachment(
    BuildContext context,
    AttachmentRead attachment,
  ) async {
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

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Parsing receipt with AI...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Download the attachment to a temporary file
      final AuthUser? user = context.read<FireflyService>().user;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final http.Request request = http.Request(
        HttpMethod.Get,
        Uri.parse(attachment.attributes.downloadUrl!),
      );
      request.headers.addAll(user.headers());

      final http.StreamedResponse resp = await httpClient.send(request);
      if (resp.statusCode != 200) {
        throw Exception('Failed to download attachment');
      }

      final List<int> fileData = [];
      await for (List<int> chunk in resp.stream) {
        fileData.addAll(chunk);
      }

      // Save to temporary file
      final Directory tmpDir = await getTemporaryDirectory();
      final File tempFile = File(
          '${tmpDir.path}/temp_receipt_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(fileData);

      // Parse with Gemini
      final GeminiService geminiService = GeminiService(
        apiKey: settings.geminiApiKey!,
        model: settings.geminiModel,
        language: settings.geminiLanguage,
      );

      final TransactionData? transactionData =
          await geminiService.parseReceipt(tempFile);

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

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
        showDialog(
          context: context,
          builder: (context) => ReceiptParseResultDialog(
            transactionData: transactionData,
            onUseData: widget.onTransactionDataParsed,
          ),
        );
      }
    } catch (e) {
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

  Future<void> _takePhotoAndParse(BuildContext context) async {
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

    try {
      // Take photo
      final ImagePicker picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (imageFile == null) {
        log.finest(() => "no image returned");
        return;
      }

      if (imageFile.path.isEmpty) {
        log.warning("Image file path is empty");
        msg.showSnackBar(
          const SnackBar(
            content: Text('Error: Unable to access image file'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Parsing receipt with AI...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Parse with Gemini
      final GeminiService geminiService = GeminiService(
        apiKey: settings.geminiApiKey!,
        model: settings.geminiModel,
        language: settings.geminiLanguage,
      );

      final File imageFileObj = File(imageFile.path);
      final TransactionData? transactionData =
          await geminiService.parseReceipt(imageFileObj);

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

        // Still offer to save the image
        if (context.mounted) {
          final bool? saveImage = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Save Image?'),
              content: const Text(
                  'AI parsing failed, but would you like to save the image as an attachment?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            ),
          );

          if (saveImage == true) {
            final PlatformFile file = PlatformFile(
              path: imageFile.path,
              name: imageFile.name,
              size: await imageFile.length(),
            );
            if (widget.transactionId == null) {
              fakeUploadAttachment(context, file);
            } else {
              uploadAttachment(context, file);
            }
          }
        }
        return;
      }

      // Show parsed data dialog
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => ReceiptParseResultDialog(
            transactionData: transactionData,
            onUseData: widget.onTransactionDataParsed,
            onSaveImage: () async {
              // Save the image as attachment
              final PlatformFile file = PlatformFile(
                path: imageFile.path,
                name: imageFile.name,
                size: await imageFile.length(),
              );
              if (widget.transactionId == null) {
                fakeUploadAttachment(context, file);
              } else {
                uploadAttachment(context, file);
              }
            },
          ),
        );
      }
    } catch (e) {
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

  /// Clean up old cached preview files to prevent disk space issues
  Future<void> _cleanupOldCachedFiles() async {
    try {
      final Directory tmpDir = await getTemporaryDirectory();
      final List<FileSystemEntity> files = tmpDir.listSync();

      for (FileSystemEntity entity in files) {
        if (entity is File && entity.path.contains('attachment_preview_')) {
          final DateTime lastModified = await entity.lastModified();
          final Duration age = DateTime.now().difference(lastModified);

          // Delete files older than 24 hours
          if (age.inHours > 24) {
            try {
              await entity.delete();
              log.fine("Cleaned up old cached preview: ${entity.path}");
            } catch (e) {
              log.warning("Failed to delete old cached file: $e");
            }
          }
        }
      }
    } catch (e) {
      log.warning("Error cleaning up cached files: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    // Clean up old cached files when dialog opens
    _cleanupOldCachedFiles();
  }

  @override
  Widget build(BuildContext context) {
    log.finest(() => "build(transactionId: ${widget.transactionId})");
    final List<Widget> attachmentCards = <Widget>[];
    final List<Widget> progressIndicators = <Widget>[];

    // Build attachment cards
    for (int i = 0; i < widget.attachments.length; i++) {
      final AttachmentRead attachment = widget.attachments[i];
      String subtitle = "";
      final DateTime? modDate =
          attachment.attributes.updatedAt ?? attachment.attributes.createdAt;
      if (modDate != null) {
        subtitle = DateFormat.yMd().add_Hms().format(modDate.toLocal());
      }

      if (attachment.attributes.size != null) {
        subtitle = "$subtitle (${filesize(attachment.attributes.size)})";
      }

      final bool isImage = _isImageAttachment(attachment);
      final bool isUploading = _dlProgress[i] != null && _dlProgress[i]! < 0;

      attachmentCards.add(
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              // Image preview for image attachments
              if (isImage)
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: _buildImagePreview(attachment),
                  ),
                ),

              // File info and actions
              ListTile(
                enabled: !isUploading,
                leading: Icon(
                  isUploading
                      ? Icons.upload
                      : isImage
                          ? Icons.image
                          : Icons.attach_file,
                ),
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
                trailing: isUploading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Parse button for image attachments only
                          if (isImage)
                            IconButton(
                              icon: const Icon(Icons.auto_awesome),
                              tooltip: 'Parse with AI',
                              onPressed: () async =>
                                  parseReceiptAttachment(context, attachment),
                            ),
                          // View/Download button
                          IconButton(
                            icon: Icon(
                                isImage ? Icons.visibility : Icons.download),
                            tooltip: isImage ? 'View' : 'Download',
                            onPressed: isImage
                                ? () => viewImageAttachment(context, attachment)
                                : widget.transactionId == null
                                    ? () async => fakeDownloadAttachment(
                                        context, attachment)
                                    : () async => downloadAttachment(
                                        context, attachment, i),
                          ),
                          // Delete button
                          IconButton(
                            icon: const Icon(Icons.delete),
                            tooltip: 'Delete',
                            onPressed: widget.transactionId == null
                                ? () async => fakeDeleteAttachment(context, i)
                                : () async =>
                                    deleteAttachment(context, attachment, i),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );

      // Progress indicator
      if (_dlProgress[i] != null) {
        progressIndicators.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: LinearProgressIndicator(
              value: _dlProgress[i]!.abs(),
            ),
          ),
        );
      }
    }

    // Build empty state widget
    final Widget emptyStateWidget = Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Icon(
            Icons.smart_toy,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
          ),
          const SizedBox(height: 16),
          Text(
            'Smart Receipt Processing',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Take a photo of your receipt and let AI automatically extract transaction details like amount, merchant, date, and category.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tips_and_updates,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tip: Use "Take Photo & Parse" for best results',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Build action buttons widget
    final Widget actionButtonsWidget = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Primary action buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    // Combined functionality: take photo and parse
                    final SettingsProvider settings =
                        context.read<SettingsProvider>();
                    final ScaffoldMessengerState msg =
                        ScaffoldMessenger.of(context);

                    // Check if Gemini API is configured
                    if (settings.geminiApiKey == null ||
                        settings.geminiApiKey!.isEmpty) {
                      msg.showSnackBar(
                        SnackBar(
                          content: const Text(
                              'Please configure Gemini AI in settings first'),
                          action: SnackBarAction(
                            label: 'Settings',
                            onPressed: () {
                              Navigator.of(context)
                                  .pushNamed('/settings/gemini');
                            },
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }

                    // Take photo and parse
                    await _takePhotoAndParse(context);
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo & Parse'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Secondary action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ImagePicker picker = ImagePicker();
                    final XFile? imageFile = await picker.pickImage(
                      source: ImageSource.camera,
                    );

                    if (imageFile == null) {
                      log.finest(() => "no image returned");
                      return;
                    }

                    log.finer(() => "Image ${imageFile.path} will be uploaded");
                    final PlatformFile file = PlatformFile(
                      path: imageFile.path,
                      name: imageFile.name,
                      size: await imageFile.length(),
                    );
                    if (context.mounted) {
                      if (widget.transactionId == null) {
                        fakeUploadAttachment(context, file);
                      } else {
                        uploadAttachment(context, file);
                      }
                    }
                  },
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Camera Only'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final FilePickerResult? file =
                        await FilePicker.platform.pickFiles();
                    if (file == null || file.files.first.path == null) {
                      return;
                    }
                    if (context.mounted) {
                      if (widget.transactionId == null) {
                        fakeUploadAttachment(context, file.files.first);
                      } else {
                        uploadAttachment(context, file.files.first);
                      }
                    }
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload File'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

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
            ? Column(
                children: [
                  Expanded(child: emptyStateWidget),
                  actionButtonsWidget,
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  ...attachmentCards,
                  ...progressIndicators,
                ],
              ),
        bottomNavigationBar: widget.attachments.isNotEmpty
            ? Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).shadowColor.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(child: actionButtonsWidget),
              )
            : null,
      ),
    );
  }

  void viewImageAttachment(
      BuildContext context, AttachmentRead attachment) async {
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
                icon: const Icon(Icons.download),
                onPressed: () {
                  Navigator.of(context).pop();
                  if (widget.transactionId == null) {
                    fakeDownloadAttachment(context, attachment);
                  } else {
                    downloadAttachment(context, attachment,
                        widget.attachments.indexOf(attachment));
                  }
                },
              ),
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
}

class AttachmentDeletionConfirmDialog extends StatelessWidget {
  const AttachmentDeletionConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.delete),
      title: Text(S.of(context).transactionDialogAttachmentsDelete),
      clipBehavior: Clip.hardEdge,
      actions: <Widget>[
        TextButton(
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
          child: Text(MaterialLocalizations.of(context).deleteButtonTooltip),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
      content: Text(S.of(context).transactionDialogAttachmentsDeleteConfirm),
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
              onUseData!(transactionData);
            } else {
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
