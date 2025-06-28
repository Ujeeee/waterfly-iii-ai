import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'package:waterflyiii/generated/l10n/app_localizations.dart';
import 'package:waterflyiii/pages/transaction.dart';
import 'package:waterflyiii/services/gemini_service.dart';
import 'package:waterflyiii/settings.dart';

final Logger log = Logger("Pages.AiReceiptParser");

class AiReceiptParserPage extends StatefulWidget {
  const AiReceiptParserPage({super.key, this.accountId});

  final String? accountId;

  @override
  State<AiReceiptParserPage> createState() => _AiReceiptParserPageState();
}

class _AiReceiptParserPageState extends State<AiReceiptParserPage> {
  File? _selectedFile;
  TransactionData? _parsedData;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();
    final S l10n = S.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiReceiptParsingTitle),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Parsing receipt with AI...'),
                ],
              ),
            )
          : _buildContent(context, settings, l10n, theme),
    );
  }

  Widget _buildContent(BuildContext context, SettingsProvider settings, S l10n,
      ThemeData theme) {
    if (_parsedData != null) {
      return _buildParsedDataView(context, l10n, theme);
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Header section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.smart_toy,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.aiReceiptParsingTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.aiReceiptParsingSubtitle,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Selected file display
          if (_selectedFile != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.image,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedFile!.path.split('/').last,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedFile = null;
                        _parsedData = null;
                      });
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Action buttons
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_selectedFile == null) ...[
                  // File selection buttons
                  _buildActionButton(
                    context: context,
                    icon: Icons.camera_alt,
                    label: 'Take Photo',
                    onPressed: () => _takePhoto(context, settings),
                    isPrimary: true,
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    context: context,
                    icon: Icons.upload_file,
                    label: 'Upload Image',
                    onPressed: () => _uploadFile(context, settings),
                    isPrimary: false,
                  ),
                ] else ...[
                  // Parse button
                  _buildActionButton(
                    context: context,
                    icon: Icons.smart_toy,
                    label: 'Parse Receipt with AI',
                    onPressed: () => _parseReceipt(context, settings),
                    isPrimary: true,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedFile = null;
                      });
                    },
                    child: const Text('Choose Different Image'),
                  ),
                ],
              ],
            ),
          ),

          // Skip option
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => _skipToManualEntry(context),
            child: const Text('Skip AI parsing and create manually'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    if (isPrimary) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
    } else {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
    }
  }

  Widget _buildParsedDataView(BuildContext context, S l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Successfully extracted transaction data!',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Parsed data display
          Text(
            'Extracted Information:',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              children: [
                if (_parsedData!.merchant != null)
                  _buildDataTile(
                      'Merchant', _parsedData!.merchant!, Icons.store),
                if (_parsedData!.amount != null)
                  _buildDataTile(
                    'Amount',
                    _parsedData!.currency != null
                        ? '${_parsedData!.currency} ${_parsedData!.amount!.toStringAsFixed(2)}'
                        : _parsedData!.amount!.toStringAsFixed(2),
                    Icons.attach_money,
                  ),
                if (_parsedData!.date != null)
                  _buildDataTile(
                    'Date',
                    DateFormat.yMd().format(_parsedData!.date!),
                    Icons.calendar_today,
                  ),
                if (_parsedData!.category != null)
                  _buildDataTile(
                      'Category', _parsedData!.category!, Icons.category),
                if (_parsedData!.description != null)
                  _buildDataTile('Description', _parsedData!.description!,
                      Icons.description),
                if (_parsedData!.paymentMethod != null)
                  _buildDataTile('Payment Method', _parsedData!.paymentMethod!,
                      Icons.payment),
                if (_parsedData!.notes != null)
                  _buildDataTile('Notes', _parsedData!.notes!, Icons.notes),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => _retryParsing(context),
                  child: const Text('Parse Again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => _proceedToTransactionForm(context),
                  child: const Text('Create Transaction'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataTile(String label, String value, IconData icon) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _takePhoto(
      BuildContext context, SettingsProvider settings) async {
    if (!_isGeminiConfigured(context, settings)) return;

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (imageFile != null && imageFile.path.isNotEmpty) {
        setState(() {
          _selectedFile = File(imageFile.path);
          _parsedData = null;
        });
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, 'Failed to take photo: $e');
      }
    }
  }

  Future<void> _uploadFile(
      BuildContext context, SettingsProvider settings) async {
    if (!_isGeminiConfigured(context, settings)) return;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _parsedData = null;
        });
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, 'Failed to upload file: $e');
      }
    }
  }

  Future<void> _parseReceipt(
      BuildContext context, SettingsProvider settings) async {
    if (_selectedFile == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final GeminiService geminiService = GeminiService(
        apiKey: settings.geminiApiKey!,
        model: settings.geminiModel,
      );

      final TransactionData? result =
          await geminiService.parseReceipt(_selectedFile!);

      setState(() {
        _isLoading = false;
        _parsedData = result;
      });

      if (result == null && context.mounted) {
        _showErrorSnackBar(
            context, 'Could not extract transaction data from the image');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (context.mounted) {
        _showErrorSnackBar(context, 'Error parsing receipt: $e');
      }
    }
  }

  void _retryParsing(BuildContext context) {
    setState(() {
      _parsedData = null;
    });
  }

  void _proceedToTransactionForm(BuildContext context) {
    // For now, just show a success message and navigate to regular transaction form
    // In the future, this will pass the parsed data to pre-populate the form
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Parsed data: ${_parsedData?.description ?? "No data"}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Navigate to transaction form
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TransactionPage(
          accountId: widget.accountId,
          initialData: _parsedData,
          receiptFile: _selectedFile,
        ),
      ),
    );
  }

  void _skipToManualEntry(BuildContext context) {
    // Navigate to regular transaction form
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TransactionPage(accountId: widget.accountId),
      ),
    );
  }

  bool _isGeminiConfigured(BuildContext context, SettingsProvider settings) {
    if (settings.geminiApiKey == null || settings.geminiApiKey!.isEmpty) {
      _showGeminiConfigurationDialog(context);
      return false;
    }
    return true;
  }

  void _showGeminiConfigurationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.settings),
        title: const Text('Gemini AI Configuration Required'),
        content: const Text(
          'To use AI receipt parsing, please configure your Gemini API key in settings first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/settings/gemini');
            },
            child: const Text('Go to Settings'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Dismiss',
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }
}
