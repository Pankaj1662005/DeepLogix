import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:world7/screens/Widgets/all_3_info_card.dart';
import 'package:world7/screens/Widgets/keywords.dart';

import '../0 theme/theme_provider.dart';

class SpeechRecognitionScreen extends StatefulWidget {
  @override
  _SpeechRecognitionScreenState createState() =>
      _SpeechRecognitionScreenState();
}

class _SpeechRecognitionScreenState extends State<SpeechRecognitionScreen> {
  String recognizedText = '';
  bool isLoading = false;
  late Directory audioDirectory;
  late Timer folderCheckTimer;
  final Random _random = Random();
  Timer? _timer;
  // Hardcoded values as requested
  final List<int> specificPastScores = [38, 78, 42, 54, 19];
  bool _showPDInfo = false;

  double currentPitch = 200; // starting values
  int currentSpeechRate = 120;
  double currentVolume = 70;


  @override
  void initState() {
    super.initState();
    requestPermissions(); // Request storage permission
    _initializeAudioDirectory();
    _startFolderWatcher();
    // Update every second
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        currentPitch = _updateValue(currentPitch, 80, 300);
        currentSpeechRate =
            _updateValue(currentSpeechRate.toDouble(), 80, 200).toInt();
        currentVolume = _updateValue(currentVolume, 50, 100);
      });
    });
  }

  double _updateValue(double value, double min, double max) {
    // Random + or - 5
    double change = _random.nextInt(11) - 5; // range -5 to +5
    double newValue = value + change;
    return newValue.clamp(min, max); // keep in range
  }

  // Request permissions for storage access
  Future<void> requestPermissions() async {
    // Check if the app has permission to access storage
    PermissionStatus status = await Permission.storage.request();
    if (status.isGranted) {
      print("Storage permission granted");
    } else {
      print("Storage permission denied");
    }
    // If the app is running on Android 11 (API level 30) or above, request MANAGE_EXTERNAL_STORAGE permission
    if (Platform.isAndroid && await Permission.manageExternalStorage.isDenied) {
      PermissionStatus manageStoragePermission = await Permission
          .manageExternalStorage.request();
      if (manageStoragePermission.isGranted) {
        print("All files access granted");
      } else {
        print("All files access denied");
      }
    }
  }

  // Initialize the audio directory path (accessing the "Documents" folder)
  Future<void> _initializeAudioDirectory() async {
    final directory = Directory(
        '/storage/emulated/0/Documents'); // Access the Documents directory
    audioDirectory = directory;

    if (!await audioDirectory.exists()) {
      print("Directory does not exist.");
    } else {
      print("Directory exists: ${audioDirectory.path}");
    }
  }

  // Start a periodic timer to check the folder for new audio files
  void _startFolderWatcher() {
    folderCheckTimer = Timer.periodic(Duration(seconds: 50), (timer) {
      _checkForNewFiles();
    });
  }

  // Check for new .wav files in the folder and process them
  Future<void> _checkForNewFiles() async {
    try {
      List<FileSystemEntity> files = audioDirectory.listSync();

      if (files.isEmpty) {
        print('No files found in directory.');
      } else {
        print('Files found in directory:');
        for (var fileEntity in files) {
          if (fileEntity is File && fileEntity.path.endsWith('.wav')) {
            print('Found file: ${fileEntity.path}');
            bool isProcessed = await sendAudioFile(fileEntity);

            // Delete the file only after successful processing
            if (isProcessed) {
              await fileEntity.delete();
              print('File deleted: ${fileEntity.path}');
            }
          }
        }
      }
    } catch (e) {
      print('Error while checking for files: $e');
    }
  }

  // Function to send the audio file to the server
  Future<bool> sendAudioFile(File audioFile) async {
    setState(() {
      isLoading = true; // Show loading indicator
    });

    try {
      var uri = Uri.parse('https://e25ad98b641b.ngrok-free.app/recognize');
      var request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

      var response = await request.send();

      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var jsonResponse = json.decode(responseData);

        setState(() {
          recognizedText = jsonResponse['recognized_text'];
          isLoading = false; // Hide loading indicator
        });

        // Get the current user ID from Firebase Auth
        String userId = FirebaseAuth.instance.currentUser!.uid;

        // Store recognized text to Firestore
        await FirebaseFirestore.instance.collection('recognized_texts').add({
          'userId': userId, // Add userId to the document
          'text': jsonResponse['recognized_text'],
          'timestamp': FieldValue.serverTimestamp(),
        });

        return true; // Indicate that the file was successfully processed
      } else {
        setState(() {
          recognizedText =
          'file has music in it or voice is not clear Error: ${response
              .statusCode}';
          isLoading = false; // Hide loading indicator
        });
        return false; // Indicate that there was an error during processing
      }
    } catch (e) {
      setState(() {
        recognizedText = 'Error: $e';
        isLoading = false; // Hide loading indicator
      });
      return false; // Indicate that there was an error during processing
    }
  }

  // Function to handle the logout confirmation dialog
  Future<void> _showLogoutDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Logout'),
          content: Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut(); // Log out the user
                Navigator.of(context).pop(); // Close the dialog
                // Optionally, you can navigate to the login screen if needed
              },
              child: Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    folderCheckTimer.cancel(); // Stop the timer when the screen is disposed
    _timer?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final isDarkMode = Provider
        .of<ThemeProvider>(context)
        .isDarkMode;
    return Scaffold(
      backgroundColor: isDarkMode
          ? Colors.black12.withOpacity(0.7)
          : Colors.black12.withOpacity(0.5),

      appBar: AppBar(
        title: Text(
          'DeepLogix Home',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.exit_to_app, color: Colors.white),
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.blue))
          : SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Profile Header
            _buildProfileHeader(),
            SizedBox(height: 24),

            // Today's Overview Cards
            DailyOverviewWidget(),
            SizedBox(height: 24),


            // Real-time Voice Metrics
            _buildRealTimeMetrics(),
            SizedBox(height: 25),

            // Emotional Timeline
            _buildProductivityTimeline(),
            SizedBox(height: 24),


            // Recent Keywords
            //_buildRecentKeywords(),
            //SizedBox(height: 24),

            KeywordsWidget(),
            SizedBox(height: 24),

            // Communication Patterns
            //_buildCommunicationPatterns(),
            SizedBox(height: 24),


          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Active since: 8:30 AM',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  'Recording time: 1h 32m',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green, width: 1),
            ),
            child: Text(
              'Active',
              style: TextStyle(color: Colors.green, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealTimeMetrics() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFFFF9800).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                    Icons.graphic_eq, color: Color(0xFFFF9800), size: 20),
              ),
              SizedBox(width: 12),
              Text(
                'Live Voice Analysis',
                style: TextStyle(color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('LIVE', style: TextStyle(color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildAnimatedMetricCard(
                  'Pitch', '${currentPitch.toInt()} Hz', Color(0xFF9C27B0),
                  Icons.waves)),
              SizedBox(width: 12),
              // Expanded(child: _buildAnimatedMetricCard('Rate', '${currentSpeechRate} WPM', Color(0xFF4CAF50), Icons.speed)),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildAnimatedMetricCard(
                  'Volume', '${currentVolume.toInt()} dB', Color(0xFF2196F3),
                  Icons.volume_up)),
              SizedBox(width: 12),
              Expanded(child: _buildAnimatedMetricCard(
                  'Quality', 'not Clear', Color(0xFFFF9800),
                  Icons.check_circle)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedMetricCard(String title, String value, Color color,
      IconData icon) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 600),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              SizedBox(width: 6),
              Text(title,
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 11)),
            ],
          ),
          SizedBox(height: 8),
          Text(value, style: TextStyle(
              color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Color _metricColor(double value) {
    if (value < 0.30) return Colors.redAccent;
    if (value < 0.50) return Colors.orange;
    if (value < 0.70) return Colors.blue;
    return Colors.green;
  }

  Widget _buildOverviewCards(List<String> texts) {
    final double vds = calculateVocabularyDiversityScore(texts);
    final String vdsLabel = vocabularyDiversityLabel(vds);

    final double tfi = calculateTopicFocusIndex(texts);
    final String tfiLabel = topicFocusLabel(tfi);

    final double lss = calculateLinguisticSignalStrength(texts);
    final String lssLabel = linguisticSignalLabel(lss);

    return Row(
      children: [
        Expanded(
          child: _buildOverviewCard(
            'Vocabulary Diversity',
            vdsLabel,
            '${(vds * 100).toStringAsFixed(1)}%',
            _metricColor(vds),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildOverviewCard(
            'Topic Focus Index',
            tfiLabel,
            '${(tfi * 100).toStringAsFixed(1)}%',
            _metricColor(tfi),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildOverviewCard(
            'Linguistic Signal',
            lssLabel,
            '${(lss * 100).toStringAsFixed(1)}%',
            _metricColor(lss),
          ),
        ),
      ],
    );
  }


  Widget _buildOverviewCard(String title, String value, String percentage,
      Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white70, fontSize: 12)),
          SizedBox(height: 8),
          Text(value, style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text(percentage, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  final Set<String> engineeringKeywords = {
    // General Engineering
    'engineering', 'engineer', 'technology', 'technical', 'innovation',
    'design', 'development', 'analysis', 'optimization', 'automation',
    'solution', 'architecture', 'framework', 'infrastructure',

    // Programming & Software
    'code', 'coding', 'program', 'programming', 'software',
    'application', 'app', 'backend', 'frontend', 'fullstack',
    'library', 'package', 'module', 'dependency', 'version',
    'compiler', 'interpreter', 'runtime', 'syntax', 'semantic',

    // Algorithms & Data Structures
    'algorithm', 'data', 'dataset', 'datastructure', 'array',
    'list', 'stack', 'queue', 'tree', 'graph', 'hashmap',
    'sorting', 'searching', 'recursion', 'iteration', 'complexity',
    'big-o', 'optimization',

    // Debugging & Testing
    'debug', 'debugging', 'bug', 'error', 'exception',
    'testing', 'unittest', 'integration', 'qa', 'validation',
    'logging', 'monitoring', 'profiling',

    // Systems & OS
    'system', 'kernel', 'process', 'thread', 'concurrency',
    'parallelism', 'memory', 'storage', 'filesystem',
    'operatingsystem', 'linux', 'windows', 'macos',

    // Networking & Web
    'network', 'protocol', 'http', 'https', 'tcp', 'udp',
    'ip', 'dns', 'socket', 'request', 'response',
    'rest', 'graphql', 'api', 'webhook',

    // Databases & Cloud
    'database', 'db', 'sql', 'nosql', 'query',
    'index', 'transaction', 'schema', 'migration',
    'server', 'client', 'cloud', 'aws', 'azure', 'gcp',
    'firebase', 'docker', 'kubernetes', 'deployment', 'scalability',

    // Mobile & UI
    'mobile', 'android', 'ios', 'ui', 'ux',
    'widget', 'layout', 'component', 'state',
    'navigation', 'responsive', 'accessibility',

    // Flutter / Cross-platform
    'flutter', 'dart', 'widgettree', 'stateless',
    'stateful', 'provider', 'bloc', 'cubit',
    'riverpod', 'mvvm', 'cleanarchitecture',

    // AI / ML / Data Science
    'ai', 'artificialintelligence', 'ml', 'machinelearning',
    'deeplearning', 'neuralnetwork', 'model',
    'training', 'inference', 'prediction',
    'nlp', 'computervision', 'dataset',
    'classification', 'regression', 'clustering',

    // Security
    'security', 'encryption', 'authentication', 'authorization',
    'token', 'jwt', 'oauth', 'hashing',
    'firewall', 'vulnerability',

    // Hardware & Embedded
    'hardware', 'processor', 'cpu', 'gpu',
    'microcontroller', 'embedded', 'firmware',
    'sensor', 'circuit', 'electronics',
    'robotics', 'iot',

    // Project & DevOps
    'project', 'task', 'requirement', 'specification',
    'agile', 'scrum', 'kanban', 'sprint',
    'git', 'github', 'gitlab', 'ci', 'cd',
    'pipeline', 'build', 'release',

    // Math & Logic
    'math', 'logic', 'boolean', 'binary',
    'calculation', 'probability', 'statistics',
    'linearalgebra', 'calculus'
  };

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

  Future<List<String>> fetchTodaysTexts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final snapshot = await FirebaseFirestore.instance
        .collection('recognized_texts')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .get();

    return snapshot.docs
        .map((doc) => (doc['text'] as String?) ?? '')
        .toList();
  }
  double calculatePDScore(List<String> texts) {
    if (texts.isEmpty) return 0;

    // ---------- KEYWORD EXTRACTION ----------
    final Map<String, int> keywordFreq = _extractKeywordFrequency(texts);

    int totalWords = 0;
    keywordFreq.forEach((_, count) => totalWords += count);

    if (totalWords == 0) return 0;

    // ---------- 1. KEYWORD RELEVANCE ----------
    int engineeringWordCount = 0;
    keywordFreq.forEach((word, count) {
      if (engineeringKeywords.contains(word)) {
        engineeringWordCount += count;
      }
    });

    double keywordRelevance =
        engineeringWordCount / totalWords; // 0–1

    // ---------- 2. VOCABULARY DIVERSITY ----------
    int uniqueWords = keywordFreq.keys.length;
    double vocabDiversity =
    (uniqueWords / totalWords).clamp(0.0, 1.0);

    // ---------- 3. SPEECH ACTIVITY ----------
    // Normalize: 300 words/day considered "active"
    double activityScore =
    (totalWords / 300).clamp(0.0, 1.0);

    // ---------- FINAL PD SCORE ----------
    double pdScore =
        (keywordRelevance * 0.4 +
            vocabDiversity * 0.3 +
            activityScore * 0.3) * 100;

    return pdScore.clamp(0, 100);
  }


  Widget _buildProductivityTimeline() {
    return FutureBuilder<List<String>>(
      future: fetchTodaysTexts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }

        final todayTexts = snapshot.data!;
        final double pdScoreToday = calculatePDScore(todayTexts);
        final double intensityToday =
        (pdScoreToday / 100).clamp(0.0, 1.0);

        DateTime now = DateTime.now();
        List<Widget> timelineBars = [];

        // ---- Past 5 Days (demo history – acceptable) ----
        final List<int> pastScores = [42, 55, 38, 61, 47];

        for (int i = 5; i >= 1; i--) {
          DateTime pastDate = now.subtract(Duration(days: i));
          String dayLabel = _getDayName(pastDate.weekday);

          int score = pastScores[5 - i];
          double intensity = score / 100.0;

          timelineBars.add(
            _buildDailyBar(dayLabel, intensity, false),
          );
        }

        // ---- Today ----
        timelineBars.add(
          _buildDailyBar(
            'Today',
            intensityToday,
            true,
            displayScore: pdScoreToday.toStringAsFixed(0),
          ),
        );

        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color(0xFF1A1F3A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- HEADER ----------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Productivity Daily Timeline',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 10),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showPDInfo = !_showPDInfo;
                      });
                    },
                    child: Container(
                      padding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blueAccent),
                      ),
                      child: Row(
                        children: [
                          Text(
                            "PD Score",
                            style: TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            _showPDInfo
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.blueAccent,
                            size: 16,
                          )
                        ],
                      ),
                    ),
                  )
                ],
              ),

              // ---------- INFO PANEL ----------
              AnimatedCrossFade(
                firstChild: SizedBox.shrink(),
                secondChild: Container(
                  margin: EdgeInsets.only(top: 12),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.5),
                      children: [
                        TextSpan(
                          text:
                          "Algorithm: Heuristic Linguistic Productivity Model (HLP-1)\n",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.cyanAccent),
                        ),
                        TextSpan(
                          text:
                          "The PD Score is a trend-based indicator derived from your daily speech patterns. It combines:\n\n",
                        ),
                        TextSpan(
                          text: "• Keyword Relevance: ",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text:
                          "Measures how frequently profession-specific terms (engineering related vocabulary) appear in your conversations.\n\n",
                        ),
                        TextSpan(
                          text: "• Vocabulary Diversity: ",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text:
                          "Evaluates the ratio of unique meaningful words to total spoken words.\n\n",
                        ),
                        TextSpan(
                          text:
                          "The final score is normalized between 0–100 and is intended for self-reflection and trend analysis, not absolute productivity measurement.",
                        ),
                      ],
                    ),
                  ),
                ),
                crossFadeState: _showPDInfo
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: Duration(milliseconds: 300),
              ),

              SizedBox(height: 16),

              // ---------- TIMELINE ----------
              Container(
                height: 100,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: timelineBars,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimelineUI(List<Widget> timelineBars) {
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
            'Productivity Daily Timeline',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Container(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: timelineBars,
            ),
          ),
        ],
      ),
    );
  }



  // Helper to convert weekday number (1-7) to String
  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // weekday is 1-based (1=Mon, 7=Sun), list is 0-based
    return days[weekday - 1];
  }

  // Keep these helpers from before...
  double _getRandomScore() {
    return (Random().nextDouble() * 0.7) + 0.2;
  }

  Widget _buildDailyBar(String day, double intensity, bool isToday, {String? displayScore}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if(isToday && displayScore != null)
          Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              displayScore,
              style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        Container(
          width: 30,
          height: 60 * intensity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: isToday
                  ? [Colors.cyan, Colors.blue]
                  : [Colors.grey.withOpacity(0.5), Colors.grey.withOpacity(0.2)],
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: isToday ? [
              BoxShadow(color: Colors.cyan.withOpacity(0.4), blurRadius: 8, offset: Offset(0, -2))
            ] : [],
          ),
        ),
        SizedBox(height: 8),
        Text(
            day,
            style: TextStyle(
                color: isToday ? Colors.white : Colors.white54,
                fontSize: 10,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal
            )
        ),
      ],
    );
  }

  //Calculate VDS
  double calculateVocabularyDiversityScore(List<String> texts) {
    if (texts.isEmpty) return 0.0;

    final Map<String, int> keywordFreq = _extractKeywordFrequency(texts);

    int totalWords = 0;
    keywordFreq.forEach((_, count) => totalWords += count);

    if (totalWords == 0) return 0.0;

    int uniqueWords = keywordFreq.keys.length;

    return (uniqueWords / totalWords).clamp(0.0, 1.0);
  }

  String vocabularyDiversityLabel(double score) {
    if (score < 0.30) return 'Weak';
    if (score < 0.50) return 'Moderate';
    if (score < 0.70) return 'Strong';
    return 'Advanced';
  }
  double calculateTopicFocusIndex(List<String> texts) {
    if (texts.isEmpty) return 0.0;

    final Map<String, int> keywordFreq = _extractKeywordFrequency(texts);
    if (keywordFreq.isEmpty) return 0.0;

    int totalCount = 0;
    keywordFreq.forEach((_, count) => totalCount += count);

    final List<int> sortedCounts =
    keywordFreq.values.toList()..sort((a, b) => b.compareTo(a));

    int topKeywordSum = 0;
    for (int i = 0; i < sortedCounts.length && i < 5; i++) {
      topKeywordSum += sortedCounts[i];
    }

    return (topKeywordSum / totalCount).clamp(0.0, 1.0);
  }

  String topicFocusLabel(double score) {
    if (score < 0.30) return 'Scattered';
    if (score < 0.50) return 'Moderate';
    if (score < 0.70) return 'Focused';
    return 'Highly Focused';
  }
  double calculateLinguisticSignalStrength(List<String> texts) {
    if (texts.isEmpty) return 0.0;

    final Map<String, int> keywordFreq = _extractKeywordFrequency(texts);

    int totalWords = 0;
    keywordFreq.forEach((_, count) => totalWords += count);

    // Normalize activity: 300 words ≈ strong session
    double activityScore = (totalWords / 300).clamp(0.0, 1.0);

    double vocabDiversity = calculateVocabularyDiversityScore(texts);
    double topicFocus = calculateTopicFocusIndex(texts);

    double signalStrength =
        (activityScore * 0.4) +
            (vocabDiversity * 0.3) +
            (topicFocus * 0.3);

    return signalStrength.clamp(0.0, 1.0);
  }

  String linguisticSignalLabel(double score) {
    if (score < 0.30) return 'Weak';
    if (score < 0.50) return 'Stable';
    if (score < 0.70) return 'Strong';
    return 'Advanced';
  }


}


