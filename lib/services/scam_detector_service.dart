import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Scam detection result
class ScamDetectionResult {
  final double threatScore; // 0.0 = safe, 1.0 = scam
  final String verdict;
  final String note;
  final bool isScam;

  ScamDetectionResult({
    required this.threatScore,
    required this.verdict,
    required this.note,
    required this.isScam,
  });

  @override
  String toString() =>
      'ScamDetectionResult(score: ${threatScore.toStringAsFixed(4)}, verdict: $verdict, isScam: $isScam)';
}

/// WordPiece tokenizer for BERT - mirrors google/mobilebert-uncased tokenization
class _WordPieceTokenizer {
  final Map<String, int> _vocab = {};
  late final int _unkId;
  late final int _clsId;
  late final int _sepId;
  late final int _padId;
  final bool _doLowerCase;

  _WordPieceTokenizer({bool doLowerCase = true}) : _doLowerCase = doLowerCase;

  bool get isLoaded => _vocab.isNotEmpty;

  /// Load vocabulary from file content
  void loadVocab(String vocabContent) {
    _vocab.clear();
    final lines = vocabContent.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final token = lines[i].trimRight(); // Keep leading spaces, trim trailing
      if (token.isNotEmpty) {
        _vocab[token] = i;
      }
    }
    _unkId = _vocab['[UNK]'] ?? 100;
    _clsId = _vocab['[CLS]'] ?? 101;
    _sepId = _vocab['[SEP]'] ?? 102;
    _padId = _vocab['[PAD]'] ?? 0;
    debugPrint('Tokenizer: Loaded ${_vocab.length} vocab tokens');
  }

  /// Clean text - remove control characters, normalize whitespace
  String _clean(String text) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final code = ch.codeUnitAt(0);
      // Skip null, replacement char, control chars (except tab/newline/space)
      if (code == 0 || code == 0xFFFD) continue;
      if (code < 32 && code != 9 && code != 10 && code != 13) continue;
      // Normalize whitespace
      if (ch == '\t' || ch == '\n' || ch == '\r' || ch == ' ') {
        buffer.write(' ');
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// Check if character is punctuation
  bool _isPunctuation(String ch) {
    final code = ch.codeUnitAt(0);
    // ASCII punctuation ranges
    if ((code >= 33 && code <= 47) ||
        (code >= 58 && code <= 64) ||
        (code >= 91 && code <= 96) ||
        (code >= 123 && code <= 126)) {
      return true;
    }
    return false;
  }

  /// Basic tokenization - split on whitespace and punctuation
  List<String> _basicTokenize(String text) {
    text = _clean(text);
    if (_doLowerCase) {
      text = text.toLowerCase();
    }

    final tokens = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == ' ') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else if (_isPunctuation(ch)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(ch);
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }

  /// WordPiece tokenization for a single word
  List<int> _wordPiece(String word) {
    if (word.length > 200) return [_unkId];

    final ids = <int>[];
    int start = 0;

    while (start < word.length) {
      int end = word.length;
      int? curId;

      while (start < end) {
        final substr = (start > 0 ? '##' : '') + word.substring(start, end);
        if (_vocab.containsKey(substr)) {
          curId = _vocab[substr];
          break;
        }
        end--;
      }

      if (curId == null) {
        return [_unkId];
      }
      ids.add(curId);
      start = end;
    }
    return ids;
  }

  /// Encode text pair into input_ids and attention_mask
  /// Format: [CLS] text_a [SEP] text_b [SEP] [PAD]...
  Map<String, List<int>> encode(
    String textA,
    String? textB, {
    int maxLength = 128,
  }) {
    // Tokenize both texts
    final idsA = <int>[];
    for (final tok in _basicTokenize(textA)) {
      idsA.addAll(_wordPiece(tok));
    }

    List<int>? idsB;
    if (textB != null && textB.isNotEmpty) {
      idsB = <int>[];
      for (final tok in _basicTokenize(textB)) {
        idsB.addAll(_wordPiece(tok));
      }
    }

    // Calculate budget (subtract special tokens)
    final specials = idsB != null ? 3 : 2; // [CLS] + [SEP] + optional [SEP]
    final budget = maxLength - specials;

    // Truncate if needed (alternate between A and B, longer first)
    final mutableIdsA = List<int>.from(idsA);
    final mutableIdsB = idsB != null ? List<int>.from(idsB) : null;

    if (mutableIdsB != null) {
      while (mutableIdsA.length + mutableIdsB.length > budget) {
        if (mutableIdsA.length >= mutableIdsB.length) {
          mutableIdsA.removeLast();
        } else {
          mutableIdsB.removeLast();
        }
      }
    } else {
      while (mutableIdsA.length > budget) {
        mutableIdsA.removeLast();
      }
    }

    // Build token sequence
    final tokenIds = <int>[_clsId];
    tokenIds.addAll(mutableIdsA);
    tokenIds.add(_sepId);
    if (mutableIdsB != null) {
      tokenIds.addAll(mutableIdsB);
      tokenIds.add(_sepId);
    }

    // Pad to max_length
    final padLen = maxLength - tokenIds.length;
    tokenIds.addAll(List<int>.filled(padLen, _padId));

    // Attention mask: 1 for real tokens, 0 for padding
    final realTokenCount = maxLength - padLen;
    final attention = List<int>.filled(realTokenCount, 1, growable: true);
    attention.addAll(List<int>.filled(padLen, 0));

    return {'input_ids': tokenIds, 'attention_mask': attention};
  }
}

/// Scam Detector Service - uses ONNX model for SMS scam classification
class ScamDetectorService {
  static final ScamDetectorService instance = ScamDetectorService._init();

  final OnnxRuntime _onnxRuntime = OnnxRuntime();
  OrtSession? _session;
  final _WordPieceTokenizer _tokenizer = _WordPieceTokenizer(doLowerCase: true);

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static const int _maxLength = 128;

  ScamDetectorService._init();

  /// Initialize the model and tokenizer
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load vocabulary
      debugPrint('ScamDetector: Loading vocabulary...');
      final vocabContent = await rootBundle.loadString('assets/ml/vocab.txt');
      _tokenizer.loadVocab(vocabContent);

      // Load ONNX model from assets
      debugPrint('ScamDetector: Loading ONNX model...');
      _session = await _onnxRuntime.createSessionFromAsset(
        'assets/ml/silver_guard.onnx',
      );

      // Log model info
      debugPrint('ScamDetector: Model inputs: ${_session!.inputNames}');
      debugPrint('ScamDetector: Model outputs: ${_session!.outputNames}');

      _isInitialized = true;
      debugPrint('ScamDetector: Initialized successfully!');
    } catch (e) {
      debugPrint('ScamDetector: Initialization failed: $e');
      rethrow;
    }
  }

  /// Detect scam in an SMS
  /// [address] - Sender ID or phone number (DLT header like "JD-SBINOT" or "+919876543210")
  /// [body] - SMS message body
  /// Returns ScamDetectionResult with threat score and verdict
  Future<ScamDetectionResult> detectScam(String address, String body) async {
    if (!_isInitialized) {
      throw StateError(
        'ScamDetectorService not initialized. Call initialize() first.',
      );
    }

    if (body.trim().isEmpty) {
      return ScamDetectionResult(
        threatScore: 0.0,
        verdict: 'EMPTY',
        note: 'Empty message body',
        isScam: false,
      );
    }

    // Tokenize: header as text_a, body as text_b
    // This produces: [CLS] header_tokens [SEP] body_tokens [SEP] [PAD]...
    final encoded = address.isNotEmpty
        ? _tokenizer.encode(address, body, maxLength: _maxLength)
        : _tokenizer.encode(body, null, maxLength: _maxLength);

    // Prepare input tensors
    final inputIds = Int64List.fromList(encoded['input_ids']!);
    final attentionMask = Int64List.fromList(encoded['attention_mask']!);

    final inputIdsTensor = await OrtValue.fromList(inputIds, [1, _maxLength]);
    final attentionMaskTensor = await OrtValue.fromList(attentionMask, [
      1,
      _maxLength,
    ]);

    // Run inference
    final inputs = {
      'input_ids': inputIdsTensor,
      'attention_mask': attentionMaskTensor,
    };

    final results = await _session!.run(inputs);

    // Clean up input tensors
    await inputIdsTensor.dispose();
    await attentionMaskTensor.dispose();

    // Get threat score from output
    // The model outputs softmax probability for scam class [0.0 - 1.0]
    double threatScore = 0.0;

    if (results.isEmpty) {
      throw Exception('Failed to get model output');
    }

    // Try named output first, fallback to first output
    final outputTensor = results['threat_score'] ?? results.values.first;
    final outputData = await outputTensor.asFlattenedList();
    if (outputData.isNotEmpty) {
      threatScore = (outputData[0] as num).toDouble();
    }

    // Dispose all output tensors (once each)
    for (final tensor in results.values) {
      await tensor.dispose();
    }

    return _createResult(threatScore);
  }

  /// Create result from threat score
  ScamDetectionResult _createResult(double threatScore) {
    String verdict;
    String note;
    bool isScam;

    if (threatScore >= 0.80) {
      verdict = 'HIGH RISK SCAM';
      note = 'Strong scam indicators detected.';
      isScam = true;
    } else if (threatScore >= 0.55) {
      verdict = 'LIKELY SCAM';
      note = 'Probably a scam — exercise caution.';
      isScam = true;
    } else if (threatScore >= 0.40) {
      verdict = 'BORDERLINE';
      note = 'Ambiguous — treat with caution.';
      isScam = false; // Conservative - don't mark as scam
    } else {
      verdict = 'SAFE';
      note = 'Message looks legitimate.';
      isScam = false;
    }

    return ScamDetectionResult(
      threatScore: threatScore,
      verdict: verdict,
      note: note,
      isScam: isScam,
    );
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _isInitialized = false;
  }
}
