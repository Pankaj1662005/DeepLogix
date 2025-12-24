import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DailyOverviewWidget extends StatefulWidget {
  @override
  _DailyOverviewWidgetState createState() => _DailyOverviewWidgetState();
}

class _DailyOverviewWidgetState extends State<DailyOverviewWidget> {
  late Future<QuerySnapshot> _dataFuture;
  bool _showOverviewInfo = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchData();
  }

  Future<QuerySnapshot> _fetchData() {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance
        .collection('recognized_texts')
        .where('userId', isEqualTo: user!.uid)
        .orderBy('timestamp')
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _emptyUI();
        }

        final docs = snapshot.data!.docs;

        final Map<String, List<QueryDocumentSnapshot>> grouped = {};
        for (var doc in docs) {
          if (doc['timestamp'] == null) continue;
          final dt = (doc['timestamp'] as Timestamp).toDate();
          final key = "${dt.year}-${dt.month}-${dt.day}";
          grouped.putIfAbsent(key, () => []);
          grouped[key]!.add(doc);
        }

        if (grouped.isEmpty) return _emptyUI();

        final latestDocs = grouped[grouped.keys.last]!;
        final texts =
        latestDocs.map((d) => (d['text'] as String?) ?? '').toList();

        final vds = _vocabularyDiversity(texts);
        final tfi = _topicFocus(texts);
        final lss = _linguisticSignal(texts);

        return _overviewContainer(vds, tfi, lss);
      },
    );
  }

  // ================= SINGLE OVERVIEW CONTAINER =================

  Widget _overviewContainer(double vds, double tfi, double lss) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- HEADER ----------
          GestureDetector(
            onTap: () {
              setState(() => _showOverviewInfo = !_showOverviewInfo);
            },
            child: Row(
              children: [
                Text(
                  'Daily Linguistic Overview',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  _showOverviewInfo
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.cyanAccent,
                  size: 18,
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          // ---------- EXPLANATION (NOW FIRST) ----------
          AnimatedCrossFade(
            firstChild: SizedBox.shrink(),
            secondChild: Container(
              margin: EdgeInsets.only(top: 12, bottom: 16),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _overviewExplanation(),
            ),
            crossFadeState: _showOverviewInfo
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: Duration(milliseconds: 300),
          ),

          // ---------- METRIC CARDS ----------
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Vocabulary Diversity',
                  label: _vdsLabel(vds),
                  value: '${(vds * 100).toStringAsFixed(1)}%',
                  color: _color(vds),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _metricCard(
                  title: 'Topic Focus Index',
                  label: _tfiLabel(tfi),
                  value: '${(tfi * 100).toStringAsFixed(1)}%',
                  color: _color(tfi),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _metricCard(
                  title: 'Communication Strength',
                  label: _lssLabel(lss),
                  value: '${(lss * 100).toStringAsFixed(1)}%',
                  color: _color(lss),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= EXPLANATION =================

  Widget _overviewExplanation() {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: Colors.white70,
          fontSize: 12,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text:
            "Algorithm: Heuristic Linguistic Analytics Model (HLAM-1)\n",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.cyanAccent,
            ),
          ),
          TextSpan(
            text:
            "This overview summarizes daily speech behavior using three heuristic indicators:\n\n",
          ),
          TextSpan(
            text: "• Vocabulary Diversity\n",
            style:
            TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          TextSpan(
            text:
            "Measures lexical richness as the ratio of unique meaningful words to total words.\n\n",
          ),
          TextSpan(
            text: "• Topic Focus Index\n",
            style:
            TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          TextSpan(
            text:
            "Indicates how concentrated conversations are around dominant topics.\n\n",
          ),
          TextSpan(
            text: "• Communication Strength\n",
            style:
            TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          TextSpan(
            text:
            "A composite indicator combining speech activity, vocabulary diversity, and topic focus.\n\n",
          ),
          TextSpan(
            text:
            "All values are normalized and intended for trend visualization and self-reflection, not clinical or psychological analysis.",
          ),
        ],
      ),
    );
  }

  // ================= CONSISTENT METRIC CARD =================

  Widget _metricCard({
    required String title,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 110, // 🔒 FIXED HEIGHT
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _color(double v) {
    if (v < 0.30) return Colors.redAccent;
    if (v < 0.50) return Colors.orange;
    if (v < 0.70) return Colors.blue;
    return Colors.green;
  }

  Widget _emptyUI() => Container(
    padding: EdgeInsets.all(16),
    child: Text(
      'No overview data available',
      style: TextStyle(color: Colors.white70),
    ),
  );

  // ================= LOGIC (UNCHANGED) =================

  Map<String, int> _keywordFreq(List<String> texts) {
    final Map<String, int> map = {};
    for (var t in texts) {
      final words = t
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .split(RegExp(r'\s+'));
      for (var w in words) {
        if (w.isEmpty) continue;
        map[w] = (map[w] ?? 0) + 1;
      }
    }
    return map;
  }

  double _vocabularyDiversity(List<String> texts) {
    final freq = _keywordFreq(texts);
    final total = freq.values.fold(0, (a, b) => a + b);
    if (total == 0) return 0;
    return (freq.length / total).clamp(0.0, 1.0);
  }

  double _topicFocus(List<String> texts) {
    final freq = _keywordFreq(texts);
    if (freq.isEmpty) return 0;
    final values = freq.values.toList()..sort((a, b) => b.compareTo(a));
    final top = values.take(5).fold(0, (a, b) => a + b);
    final total = values.fold(0, (a, b) => a + b);
    return (top / total).clamp(0.0, 1.0);
  }

  double _linguisticSignal(List<String> texts) {
    final freq = _keywordFreq(texts);
    final totalWords = freq.values.fold(0, (a, b) => a + b);
    final activity = (totalWords / 300).clamp(0.0, 1.0);
    return (activity * 0.4 +
        _vocabularyDiversity(texts) * 0.3 +
        _topicFocus(texts) * 0.3)
        .clamp(0.0, 1.0);
  }

  String _vdsLabel(double v) =>
      v < 0.3 ? 'Weak' : v < 0.5 ? 'Moderate' : v < 0.7 ? 'Strong' : 'Advanced';

  String _tfiLabel(double v) =>
      v < 0.3 ? 'Scattered' : v < 0.5 ? 'Moderate' : v < 0.7 ? 'Focused' : 'High Focus';

  String _lssLabel(double v) =>
      v < 0.3 ? 'Weak' : v < 0.5 ? 'Stable' : v < 0.7 ? 'Strong' : 'Advanced';
}
