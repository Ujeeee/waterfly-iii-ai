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
    'gemini-2.5-flash',
    'gemini-1.5-flash',
    'gemini-1.5-flash-8b',
    'gemini-1.5-pro',
    'gemini-1.0-pro',
  ];

  final String _apiKey;
  final String _model;
  final String _language;
  late final GenerativeModel _generativeModel;

  GeminiService({
    required String apiKey,
    required String model,
    String language = "English",
  })  : _apiKey = apiKey,
        _model = model,
        _language = language {
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
Please analyze this receipt/invoice image and extract the following transaction information in JSON format.
${_language != "English" ? "Respond in $_language language for text fields (description, category, notes) unless the original text is clearly in another language." : ""}

{
  "description": "Short transaction title${_language != "English" ? " (in $_language)" : ""} - keep it brief, 3-8 words max",
  "amount": 0.00,
  "date": "YYYY-MM-DD",
  "merchant": "Name of the store/merchant (keep original name exactly as shown)",
  "category": "Category in Title Case${_language != "English" ? " (in $_language)" : ""} (e.g., ${_getCategoryExamples()})",
  "paymentMethod": "Payment method if visible${_language != "English" ? " (in $_language)" : ""} (${_getPaymentMethodExamples()})",
  "currency": "Currency code (e.g., ${_getCurrencyExample()})",
  "notes": "Detailed information${_language != "English" ? " (in $_language)" : ""} - include items purchased, payment details, location, or any other relevant details from receipt"
}

Rules:
- Only return valid JSON format
${_language != "English" ? "- Use $_language language for text fields when possible (except merchant name)" : ""}
- Use null for fields that cannot be determined from the image

FORMATTING REQUIREMENTS:
- description: Short title (3-8 words), used as transaction record title
- category: Use Title Case format (e.g., "Grocery Shopping", "Fuel Purchase", "Restaurant Meal")
- notes: Put all detailed information here (items bought, payment details, store location, receipt number, etc.)
- merchant: Keep exactly as written on receipt (no translation)
- amount: Extract total amount only (exclude tips unless part of total)
- date: Use ISO format (YYYY-MM-DD)
- currency: Use standard 3-letter codes${_language == "Indonesian" ? " (IDR for Indonesian Rupiah)" : ""}

If you cannot read the receipt clearly, return null for uncertain fields.

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

  String _getCategoryExamples() {
    switch (_language) {
      case "Indonesian":
        return "Belanja Kebutuhan, Bahan Bakar, Makanan & Minuman, Transportasi, Kesehatan, Pendidikan, Hiburan";
      default:
        return "Grocery Shopping, Fuel Purchase, Restaurant Meal, Transportation, Healthcare, Education, Entertainment";
    }
  }

  String _getPaymentMethodExamples() {
    switch (_language) {
      case "Indonesian":
        return "Tunai, Kartu Debit, Kartu Kredit, Transfer";
      default:
        return "Cash, Debit Card, Credit Card, Transfer";
    }
  }

  String _getCurrencyExample() {
    switch (_language) {
      case "Indonesian":
        return "IDR, USD, EUR, etc.";
      default:
        return "USD, EUR, IDR, etc.";
    }
  }
}
