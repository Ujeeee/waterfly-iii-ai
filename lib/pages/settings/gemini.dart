import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waterflyiii/services/gemini_service.dart';
import 'package:waterflyiii/settings.dart';

class GeminiSettingsPage extends StatefulWidget {
  const GeminiSettingsPage({super.key});

  @override
  State<GeminiSettingsPage> createState() => _GeminiSettingsPageState();
}

class _GeminiSettingsPageState extends State<GeminiSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _apiKeyFocusNode = FocusNode();
  bool _obscureApiKey = true;
  String? _selectedModel;
  String? _selectedLanguage;

  static const List<String> availableLanguages = [
    'English',
    'Indonesian',
    'Spanish',
    'French',
    'German',
    'Japanese',
    'Korean',
    'Chinese (Simplified)',
  ];

  @override
  void initState() {
    super.initState();
    final SettingsProvider settings = context.read<SettingsProvider>();
    _apiKeyController.text = settings.geminiApiKey ?? '';
    _selectedModel = settings.geminiModel;
    _selectedLanguage = settings.geminiLanguage;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    super.dispose();
  }

  void _saveApiKey() async {
    final SettingsProvider settings = context.read<SettingsProvider>();
    final String apiKey = _apiKeyController.text.trim();

    if (apiKey.isEmpty) {
      await settings.setGeminiApiKey(null);
      return;
    }

    if (!GeminiService.isValidApiKey(apiKey)) {
      _showErrorSnackBar('Please enter a valid API key');
      return;
    }

    await settings.setGeminiApiKey(apiKey);
    _showSuccessSnackBar('API key saved successfully');
  }

  void _saveModel(String? model) async {
    if (model == null) return;

    final SettingsProvider settings = context.read<SettingsProvider>();
    await settings.setGeminiModel(model);
    setState(() {
      _selectedModel = model;
    });
    _showSuccessSnackBar('Model saved successfully');
  }

  void _saveLanguage(String? language) async {
    if (language == null) return;

    final SettingsProvider settings = context.read<SettingsProvider>();
    await settings.setGeminiLanguage(language);
    setState(() {
      _selectedLanguage = language;
    });
    _showSuccessSnackBar('Language saved successfully');
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini AI Settings'),
        backgroundColor: theme.colorScheme.surfaceContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Gemini AI Configuration',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Configure Gemini AI to automatically extract transaction data from receipt images.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '• Automatically extract merchant names, amounts, and dates\n'
                    '• Support for multiple receipt formats\n'
                    '• Intelligent categorization of expenses\n'
                    '• Privacy-focused: images are processed by Google AI',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API Key',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    focusNode: _apiKeyFocusNode,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      hintText: 'Enter your Gemini API key',
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscureApiKey
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureApiKey = !_obscureApiKey;
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.save),
                            onPressed: _saveApiKey,
                          ),
                        ],
                      ),
                    ),
                    onSubmitted: (_) => _saveApiKey(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Get your API key from Google AI Studio (ai.google.dev)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model Selection',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ...GeminiService.availableModels.map((String model) {
                    return RadioListTile<String>(
                      title: Text(model),
                      subtitle: Text(_getModelDescription(model)),
                      value: model,
                      groupValue: _selectedModel,
                      onChanged: _saveModel,
                      dense: true,
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Response Language',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Language for AI-parsed transaction details (merchant names remain unchanged)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Select Language',
                      border: OutlineInputBorder(),
                    ),
                    items: availableLanguages.map((String language) {
                      return DropdownMenuItem<String>(
                        value: language,
                        child: Text(language),
                      );
                    }).toList(),
                    onChanged: _saveLanguage,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Privacy & Usage',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '• Receipt images are sent to Google\'s Gemini AI for processing\n'
                    '• Images are not stored by Google after processing\n'
                    '• API usage may incur costs based on Google\'s pricing\n'
                    '• Review Google AI\'s privacy policy for more details',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getModelDescription(String model) {
    switch (model) {
      case 'gemini-2.0-flash-exp':
        return 'Latest model, experimental (Recommended)';
      case 'gemini-2.5-flash':
        return 'Enhanced flash model, improved performance';
      case 'gemini-1.5-flash':
        return 'Fast, efficient processing';
      case 'gemini-1.5-flash-8b':
        return 'Fastest, lightweight model';
      case 'gemini-1.5-pro':
        return 'Most accurate, higher cost';
      case 'gemini-1.0-pro':
        return 'Previous generation model';
      default:
        return 'Gemini AI model';
    }
  }
}
