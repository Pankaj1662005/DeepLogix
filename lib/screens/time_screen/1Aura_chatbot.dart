import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';

import '../../0 theme/theme_provider.dart'; // Ensure this path is correct

class SummaryScreen extends StatefulWidget {
  @override
  _SummaryScreenState createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  TextEditingController _promptController = TextEditingController();
  List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  String _selectedDate = '';
  String _contextData = ''; // Store the selected date's data as context

  // **CRITICAL FIX: Conversation history for Gemini API**
  List<Map<String, String>> _conversationHistory = []; // Maps 'role' and 'text'

  // **SECURITY WARNING: DO NOT hardcode API keys in production Flutter apps.**
  // Use a secure environment variable or a proxy server.
  // I have replaced your public-looking key with a placeholder.
  final String geminiAPIKey = "";


  Future<void> _loadDateData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedDate.isEmpty) return;

    // Reset history when new data is loaded
    _conversationHistory.clear();

    // Your existing Firestore logic to load data for the selected date
    final snapshot = await FirebaseFirestore.instance
        .collection('recognized_texts')
        .where('userId', isEqualTo: user.uid)
        .get();

    final filtered = snapshot.docs.where((doc) {
      final ts = (doc['timestamp'] as Timestamp).toDate();
      final formatted = DateFormat('dd MMMM yyyy').format(ts);
      return formatted == _selectedDate;
    }).toList();

    if (filtered.isNotEmpty) {
      _contextData = filtered.map((e) => e['text']).join('\n');

      setState(() {
        _messages.clear();
        final initialMessage = {
          "text":
          "I've loaded the data for $_selectedDate and I'm ready to chat! Ask me anything about this data.",
          "sender": "AI"
        };
        _messages.add(initialMessage);

        // **FIX: Add initial AI message to the conversation history**
        // This acts as the first "context" turn.
        _conversationHistory.add({
          "role": "model",
          "text": initialMessage["text"]!
        });
      });
    } else {
      setState(() {
        _messages.clear();
        _messages.add({"text": "No data found for $_selectedDate", "sender": "AI"});
        _contextData = "";
      });
    }
  }


  Future<void> _sendToGemini() async {
    final inputText = _promptController.text.trim();
    if (inputText.isEmpty || _selectedDate.isEmpty || geminiAPIKey.isEmpty) return;

    // Add user message to UI and history
    setState(() {
      _messages.add({"text": inputText, "sender": "User"});
      _conversationHistory.add({"role": "user", "text": inputText}); // **FIX**
      _isLoading = true;
      _promptController.clear();
    });

    final url =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiAPIKey"; // **MODEL UPGRADE**

    // **CONVERSATION HISTORY FIX: Build the 'contents' array**
    List<Map<String, dynamic>> contents = [];

    // Convert your conversation history into the required API format
    for (var message in _conversationHistory) {
      contents.add({
        "role": message["role"],
        "parts": [
          {"text": message["text"]}
        ]
      });
    }

    // **IMPORTANT: The API requires systemInstruction and contents to be separated.**
    final requestBody = {
      "systemInstruction": { // This is sent on every turn, which is fine for context-heavy chat
        "parts": [
          {
            "text": "You are a concise assistant that answers user queries ONLY using the provided OCR data for the selected date. The full context is:\n\n$_contextData\n\nStrictly use the context above and the conversation history to answer."
          }
        ]
      },
      "contents": contents, // **FIX: Send the full history**
      "generationConfig": {
        "temperature": 0.3,
        "topP": 0.8,
        "topK": 40,
        "maxOutputTokens": 512
      }
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final reply = decoded["candidates"]?[0]?["content"]?["parts"]?[0]?["text"] ??
            "No response text found.";

        // Add AI response to UI and history
        setState(() {
          _messages.add({"text": reply, "sender": "AI"});
          _conversationHistory.add({"role": "model", "text": reply}); // **FIX**
        });
      } else {
        // Handle errors and add an error message to history
        final errorMessage = "API Error ${response.statusCode}: ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}...";
        setState(() {
          _messages.add({"text": errorMessage, "sender": "AI"});
        });
        // We do NOT add the error message to the _conversationHistory to prevent confusing the model
      }
    } catch (e) {
      // Handle network/parsing errors
      setState(() {
        _messages.add({"text": "Network Error: $e", "sender": "AI"});
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _clearDateSelection() {
    setState(() {
      _selectedDate = '';
      _contextData = '';
      _conversationHistory.clear(); // **FIX: Clear history when date is cleared**
      _messages.clear();
    });
  }

  // The rest of your code (_pickDate, _buildTypingIndicator, _buildMessageBubble, build) remains mostly the same.
  // ... (You must include the rest of your original code here)

  // The rest of your `SummaryScreen` class implementation goes here...
  // ... (specifically, the `_pickDate`, `_clearDateSelection`, `_buildTypingIndicator`, `_buildMessageBubble`, and `build` methods)

  void _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      final newDate = DateFormat('dd MMMM yyyy').format(picked);
      if (newDate != _selectedDate) {
        setState(() {
          _selectedDate = newDate;
          _messages.clear();
          _conversationHistory.clear(); // Ensure history is cleared
        });
        await _loadDateData();
      }
    }
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          SizedBox(width: 10),
          ClipOval(
            child: Transform.scale(
              scale: 1.2,
              child: Image.asset(
                'assets/alexa.gif',
                width: 20,
                height: 20,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(5),
            margin: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            child: Text(
              "Typing...",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.all(12),
        margin: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue : Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_isLoading
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedDate.isEmpty
                        ? "Select a date to chat with data!"
                        : "What can I help with?",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  if (_selectedDate.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: ElevatedButton.icon(
                        onPressed: () => _pickDate(context),
                        icon: Icon(Icons.calendar_today),
                        label: Text("Pick a Date"),
                      ),
                    ),
                ],
              ),
            )
                : ListView.builder(
              reverse: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return _buildTypingIndicator();
                }
                final message = _messages[index];
                final isUser = message["sender"] == "User";
                return _buildMessageBubble(message["text"]!, isUser);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _selectedDate.isEmpty
                          ? "Select a date first..."
                          : "Ask about your data...",
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    enabled: _selectedDate.isNotEmpty,
                    onSubmitted: (_) => _selectedDate.isNotEmpty ? _sendToGemini() : null,
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: _selectedDate.isNotEmpty ? Colors.blue : Colors.grey),
                  onPressed: () {
                    if (_promptController.text.isNotEmpty && _selectedDate.isNotEmpty) {
                      _sendToGemini();
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (_selectedDate.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.link, color: Colors.white70, size: 18),
                            SizedBox(width: 4),
                            Text(
                              _selectedDate,
                              style: TextStyle(color: Colors.white70),
                            ),
                            SizedBox(width: 4),
                            GestureDetector(
                              onTap: _clearDateSelection,
                              child: Icon(Icons.close, color: Colors.white70, size: 18),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.calendar_today, color: Colors.white),
                  onPressed: () => _pickDate(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}