import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class KeywordsWidget extends StatefulWidget {
  @override
  _KeywordsWidgetState createState() => _KeywordsWidgetState();
}

class _KeywordsWidgetState extends State<KeywordsWidget> {
  // We store the Future here so it is only created ONCE
  late Future<QuerySnapshot> _dataFuture;

  @override
  void initState() {
    super.initState();
    // Initialize the fetch logic once when the widget is first built
    _dataFuture = _fetchData();
  }

  Future<QuerySnapshot> _fetchData() {
    final user = FirebaseAuth.instance.currentUser;
    // .get() fetches the data only once!
    return FirebaseFirestore.instance
        .collection('recognized_texts')
        .where('userId', isEqualTo: user!.uid)
        .orderBy('timestamp')
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: _dataFuture, // Use the variable created in initState
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingUI();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _emptyUI();
        }

        final docs = snapshot.data!.docs;

        // ---------- GROUP BY DATE ----------
        final Map<String, List<QueryDocumentSnapshot>> grouped = {};

        for (var doc in docs) {
          // Add safety check for null timestamp
          if (doc['timestamp'] == null) continue;

          final ts = doc['timestamp'] as Timestamp;
          final dt = ts.toDate();
          final key = "${dt.year}-${dt.month}-${dt.day}";

          grouped.putIfAbsent(key, () => []);
          grouped[key]!.add(doc);
        }

        if (grouped.isEmpty) return _emptyUI();

        // Latest date
        final latestDate = grouped.keys.last;
        final latestDocs = grouped[latestDate]!;

        // Collect all text
        final allTexts =
        latestDocs.map((d) => (d['text'] as String?) ?? '').toList();

        // Extract keywords
        final keywordMap = _extractKeywordFrequency(allTexts);

        // Sort by frequency
        final newList = keywordMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // Limit to TOP 20
        final limited =
        newList.length > 20 ? newList.sublist(0, 20) : newList;

        // Determine top 5
        final top5 = newList.length > 5 ? newList.sublist(0, 5) : newList;

        // Render directly (No need for 'cachedList' checks anymore)
        return _keywordUI(limited, top5);
      },
    );
  }

  // ----------- UI CONTAINER ------------
  Widget _keywordUI(
      List<MapEntry<String, int>> entries,
      List<MapEntry<String, int>> top5List) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trending Keywords (Today)',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var e in entries)
                _buildKeywordChip(
                  e.key,
                  e.value,
                  isTop5: top5List.any((item) => item.key == e.key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------- KEYWORD CHIP -------------
  Widget _buildKeywordChip(String keyword, int count, {bool isTop5 = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isTop5
            ? Colors.orange.withOpacity(0.25)
            : Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTop5 ? Colors.orange : Colors.blue.withOpacity(0.3),
          width: isTop5 ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            keyword,
            style: TextStyle(
              color: Colors.white,
              fontSize: isTop5 ? 14 : 12,
              fontWeight: isTop5 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          SizedBox(width: 6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isTop5 ? Colors.orange : Colors.blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: Colors.white,
                fontSize: isTop5 ? 11 : 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------- KEYWORD ANALYZER --------------
  Map<String, int> _extractKeywordFrequency(List<String> texts) {
    final Map<String, int> keywordCounts = {};

    final Set<String> stopWords = {
      'a', 'about', 'above', 'after', 'again', 'against', 'all', 'am', 'an', 'and',
      'any', 'are', "aren't", 'as', 'at', 'be', 'because', 'been', 'before',
      'being', 'below', 'between', 'both', 'but', 'by', "can't", 'cannot', 'could',
      "couldn't", 'did', "didn't", 'do', 'does', "doesn't", 'doing', "don't",
      'down', 'during', 'each', 'few', 'for', 'from', 'further', 'had', "hadn't",
      'has', "hasn't", 'have', "haven't", 'having', 'he', "he'd", "he'll", "he's",
      'her', 'here', "here's", 'hers', 'herself', 'him', 'himself', 'his', 'how',
      "how's", 'i', "i'd", "i'll", "i'm", "i've", 'if', 'in', 'into', 'is',
      "isn't", 'it', "it's", 'its', 'itself', "let's", 'me', 'more', 'most',
      "mustn't", 'my', 'myself', 'no', 'nor', 'not', 'of', 'off', 'on', 'once',
      'only', 'or', 'other', 'ought', 'our', 'ours', 'ourselves', 'out', 'over',
      'own', 'same', "shan't", 'she', "she'd", "she'll", "she's", 'should',
      "shouldn't", 'so', 'some', 'such', 'than', 'that', "that's", 'the', 'their',
      'theirs', 'them', 'themselves', 'then', 'there', "there's", 'these', 'they',
      "they'd", "they'll", "they're", "they've", 'this', 'those', 'through', 'to',
      'too', 'under', 'until', 'up', 'very', 'was', "wasn't", 'we', "we'd",
      "we'll", "we're", "we've", 'were', "weren't", 'what', "what's", 'when',
      "when's", 'where', "where's", 'which', 'while', 'who', "who's", 'whom',
      'why', "why's", 'will', 'with', "won't", 'would', "wouldn't", 'you',
      "you'd", "you'll", "you're", "you've", 'your', 'yours', 'yourself',
      'yourselves',

      // Custom filler words common in speech
      'uh', 'um', 'hmm', 'okay', 'ok', 'alright', 'yeah', 'right', 'huh', 'oh',
      'well', 'like', 'just', 'really', 'actually', 'basically', 'literally'
    };

    for (var text in texts) {
      final words = text
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .split(RegExp(r'\s+'));

      for (var word in words) {
        if (word.isEmpty) continue;
        if (stopWords.contains(word)) continue;

        keywordCounts[word] = (keywordCounts[word] ?? 0) + 1;
      }
    }

    return keywordCounts;
  }

  Widget _loadingUI() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _emptyUI() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        "No keywords found for today",
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}