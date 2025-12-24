import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../0 theme/theme_provider.dart';

class Mindmapscreen extends StatefulWidget {
  const Mindmapscreen({super.key});

  @override
  State<Mindmapscreen> createState() => _MindmapscreenState();
}

class _MindmapscreenState extends State<Mindmapscreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _summaries = [];

  // TODO: Move this to a secure backend or .env file. Do not commit this key!

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  /// Load previous summaries sorted by date
  Future<void> _loadSummaries() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('summaries')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _summaries = snapshot.docs.map((doc) {
            return {
              'date': doc['date'] ?? '',
              'summary': doc['summary'] ?? '',
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Error loading summaries: $e");
    }
  }
  String buildStructuredDayText(QuerySnapshot snapshot) {
    final buffer = StringBuffer();

    for (var doc in snapshot.docs) {
      final ts = doc['timestamp'] as Timestamp?;
      final text = (doc['text'] ?? '').toString().trim();

      if (ts == null || text.isEmpty) continue;

      final time = DateFormat('hh:mm a').format(ts.toDate());
      buffer.writeln("[$time] $text");
    }

    return buffer.toString();
  }
  List<String> chunkText(String text, int maxLength) {
    final chunks = <String>[];
    for (int i = 0; i < text.length; i += maxLength) {
      chunks.add(
        text.substring(
          i,
          i + maxLength > text.length ? text.length : i + maxLength,
        ),
      );
    }
    return chunks;
  }

  static const extractionPrompt = """
You are an information extractor.

Rules:
- Extract ONLY key topics, ideas, tasks, concerns, or decisions.
- Ignore filler, emotions, casual talk, and repetition.
- Do NOT summarize.
- Do NOT explain.
- Return bullet points only.
- Each bullet must be short and factual.
""";
  static const finalSummaryPrompt = """
You are an expert daily summarizer.

Rules:
- Produce ONE daily summary.
- Title: "Daily Discussion Summary"
- Maximum 5 bullet points.
- If content is minimal, use fewer bullets.
- Each bullet ≤ 15 words.
- Merge repeated ideas.
- Use generic phrases like:
  "was discussed", "was highlighted", "important aspect".
- Focus on WHAT happened, not narration.
""";




  Future<void> _fetchAIResponse() async {
    const apiKey = "";

    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final todayFormatted = DateFormat('dd MMMM yyyy').format(now);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('recognized_texts')
          .where('userId', isEqualTo: user.uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // 1️⃣ Build clean structured text
      final structuredText = buildStructuredDayText(snapshot);

      // 2️⃣ Chunk safely
      final chunks = chunkText(structuredText, 5000);

      // 3️⃣ FIRST PASS: extract facts
      List<String> extractedPoints = [];

      for (final chunk in chunks) {
        final response = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $apiKey",
          },
          body: jsonEncode({
            "model": "llama-3.3-70b-versatile",
            "messages": [
              {"role": "system", "content": extractionPrompt},
              {"role": "user", "content": chunk}
            ],
            "temperature": 0.2,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final content = data['choices'][0]['message']['content'];
          if (content != null && content.toString().trim().isNotEmpty) {
            extractedPoints.add(content.trim());
          }
        }
      }

      if (extractedPoints.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // 4️⃣ SECOND PASS: synthesize final summary
      final synthesisResponse = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        },
        body: jsonEncode({
          "model": "llama-3.3-70b-versatile",
          "messages": [
            {"role": "system", "content": finalSummaryPrompt},
            {"role": "user", "content": extractedPoints.join("\n")}
          ],
          "temperature": 0.15,
        }),
      );

      if (synthesisResponse.statusCode != 200) {
        throw Exception("Final synthesis failed");
      }

      final finalData = jsonDecode(synthesisResponse.body);
      final finalSummary =
      finalData['choices'][0]['message']['content'].trim();

      // 5️⃣ Save summary
      final existing = await FirebaseFirestore.instance
          .collection('summaries')
          .where('userId', isEqualTo: user.uid)
          .where('date', isEqualTo: todayFormatted)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.update({
          'summary': finalSummary,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('summaries').add({
          'userId': user.uid,
          'summary': finalSummary,
          'date': todayFormatted,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      await _loadSummaries();
    } catch (e) {
      debugPrint("Summary error: $e");
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    // Access theme provider safely
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.white, // FIX: Don't use transparent
      appBar: AppBar(
        title: Text("Mindmap Summary", style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
        backgroundColor: isDarkMode ? Colors.black : Colors.white,
        iconTheme: IconThemeData(color: isDarkMode ? Colors.white : Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchAIResponse,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _summaries.isEmpty
          ? Center(
        child: Text(
          "No summaries found.",
          style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
              fontSize: 16),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _summaries.length,
        itemBuilder: (context, index) {
          final item = _summaries[index];
          return Card(
            // FIX: Dynamic color based on theme
            color: isDarkMode ? Colors.grey[900] : Colors.grey[200],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['date'],
                    style: TextStyle(
                      color: isDarkMode ? Colors.amber : Colors.deepPurple,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item['summary'],
                    style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87,
                        fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}