import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logging/logging.dart';

final Logger log = Logger("Services.Gemini");

class TransactionData {
  final String? description;
  final double? amount;
  final DateTime? date;
  final String? merchant;
  final String? category;
  final String? paymentMethod;
  final String? currency;
  final String? notes;

  TransactionData({
    this.description,
    this.amount,
    this.date,
    this.merchant,
    this.category,
    this.paymentMethod,
    this.currency,
    this.notes,
  });

  @override
  String toString() {
    return 'TransactionData{description: $description, amount: $amount, date: $date, merchant: $merchant, category: $category, paymentMethod: $paymentMethod, currency: $currency, notes: $notes}';
  }
}

class GeminiService {
  static const List<String> availableModels = [
    'gemini-2.0-flash-exp',
    'gemini-1.5-flash',
    'gemini-1.5-flash-8b',
    'gemini-1.5-pro',
    'gemini-1.0-pro',
  ];

  final String _apiKey;
  final String _model;
  late final GenerativeModel _generativeModel;

  GeminiService({
    required String apiKey,
    required String model,
  })  : _apiKey = apiKey,
        _model = model {
    _generativeModel = GenerativeModel(
      model: _model,
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        topK: 32,
        topP: 1,
        maxOutputTokens: 2048,
      ),
    );
  }

  Future<TransactionData?> parseReceipt(File imageFile) async {
    try {
      log.info("Starting receipt parsing with model $_model");

      if (!await imageFile.exists()) {
        log.severe("Image file does not exist: ${imageFile.path}");
        throw Exception("Image file not found");
      }

      final Uint8List imageBytes = await imageFile.readAsBytes();

      if (imageBytes.isEmpty) {
        log.severe("Image file is empty: ${imageFile.path}");
        throw Exception("Image file is empty");
      }

      log.fine("Image loaded, size: ${imageBytes.length} bytes");

      final String prompt = '''
Please analyze this receipt/invoice image and extract the following transaction information in JSON format:

{
  "description": "Brief description of the transaction",
  "amount": 0.00,
  "date": "YYYY-MM-DD",
  "merchant": "Name of the store/merchant",
  "category": "Category of expense (e.g., groceries, fuel, restaurant, etc.)",
  "paymentMethod": "Payment method if visible (cash, card, etc.)",
  "currency": "Currency code (e.g., USD, EUR, etc.)",
  "notes": "Any additional relevant information"
}

Rules:
- Only return valid JSON format
- Use null for fields that cannot be determined from the image
- For amount, extract the total amount (not including tips unless clearly part of total)
- For date, use ISO format (YYYY-MM-DD)
- For currency, use standard 3-letter codes
- Keep description concise but descriptive
- If you cannot read the receipt clearly, return null for uncertain fields

Extract the information from this receipt:
''';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      log.fine("Sending request to Gemini API...");
      final response = await _generativeModel.generateContent(content);
      log.fine("Received response from Gemini API");

      final String? responseText = response.text;
      if (responseText == null || responseText.isEmpty) {
        log.warning("Empty response from Gemini API");
        return null;
      }

      log.fine("Gemini response: $responseText");

      // Try to extract JSON from the response
      String cleanResponseText = responseText.trim();

      // Remove markdown code blocks if present
      if (cleanResponseText.startsWith('```json')) {
        cleanResponseText = cleanResponseText.substring(7);
      }
      if (cleanResponseText.startsWith('```')) {
        cleanResponseText = cleanResponseText.substring(3);
      }
      if (cleanResponseText.endsWith('```')) {
        cleanResponseText =
            cleanResponseText.substring(0, cleanResponseText.length - 3);
      }

      cleanResponseText = cleanResponseText.trim();

      // Parse JSON response
      try {
        final Map<String, dynamic> jsonData = json.decode(cleanResponseText);

        return TransactionData(
          description: jsonData['description'] as String?,
          amount: _parseAmount(jsonData['amount']),
          date: _parseDate(jsonData['date'] as String?),
          merchant: jsonData['merchant'] as String?,
          category: jsonData['category'] as String?,
          paymentMethod: jsonData['paymentMethod'] as String?,
          currency: jsonData['currency'] as String?,
          notes: jsonData['notes'] as String?,
        );
      } catch (e) {
        log.severe("Failed to parse JSON response: $e");
        log.severe("Response text: $cleanResponseText");
        return null;
      }
    } catch (e, stackTrace) {
      log.severe("Error parsing receipt with Gemini", e, stackTrace);
      return null;
    }
  }

  double? _parseAmount(dynamic amount) {
    if (amount == null) return null;
    if (amount is double) return amount;
    if (amount is int) return amount.toDouble();
    if (amount is String) {
      // Remove currency symbols and parse
      String cleanAmount = amount.replaceAll(RegExp(r'[^\d.,]'), '');
      return double.tryParse(cleanAmount.replaceAll(',', '.'));
    }
    return null;
  }

  DateTime? _parseDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;

    try {
      // Try ISO format first
      return DateTime.parse(dateString);
    } catch (e) {
      // Try other common formats
      List<RegExp> patterns = [
        RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'), // YYYY-MM-DD
        RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})'), // MM/DD/YYYY
        RegExp(r'(\d{1,2})-(\d{1,2})-(\d{4})'), // MM-DD-YYYY
        RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})'), // MM.DD.YYYY
      ];

      for (RegExp pattern in patterns) {
        Match? match = pattern.firstMatch(dateString);
        if (match != null) {
          try {
            if (pattern == patterns[0]) {
              // YYYY-MM-DD
              return DateTime(
                int.parse(match.group(1)!),
                int.parse(match.group(2)!),
                int.parse(match.group(3)!),
              );
            } else {
              // MM/DD/YYYY or similar
              return DateTime(
                int.parse(match.group(3)!),
                int.parse(match.group(1)!),
                int.parse(match.group(2)!),
              );
            }
          } catch (e) {
            continue;
          }
        }
      }

      log.warning("Could not parse date: $dateString");
      return null;
    }
  }

  static bool isValidApiKey(String apiKey) {
    // Basic validation - API keys should be non-empty strings
    return apiKey.isNotEmpty && apiKey.length > 10;
  }
}
