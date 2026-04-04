import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://klyrasrqgxijwrxuoevj.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtseXJhc3JxZ3hpandyeHVvZXZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI4ODUyMzcsImV4cCI6MjA2ODQ2MTIzN30.qjeTrLp_QquSwvF09HrrQd-stPtgu6H51-Zdb4JUeSM',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '霜蓝AI',
      theme: ThemeData.dark(),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final supabase = Supabase.instance.client;
  bool useReasoner = false;
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  bool isGenerating = false;

  Future<void> loadMessages() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('messages')
        .select()
        .eq('user_id', user.id)
        .order('created_at');

    setState(() {
      messages = (data as List)
          .map((e) => {"text": e['content'], "isUser": e['is_user']})
          .toList();
    });

    scrollToBottom();
  }

  Future<void> signInWithGitHub() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.github,
      redirectTo: 'io.supabase.flutter://login-callback/',
    );
  }

  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.flutter://login-callback/',
    );
  }

  @override
  void initState() {
    super.initState();
    loadMessages();
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    isGenerating = true;

    setState(() {
      messages.add({"text": text, "isUser": true});
      messages.add({
        "text": useReasoner ? "深度思考中..." : "思考中...",
        "isUser": false,
      });
    });

    final user = supabase.auth.currentUser;
    if (user != null) {
      await supabase.from('messages').insert({
        'user_id': user.id,
        'content': text,
        'is_user': true,
      });
    }

    controller.clear();
    scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse("https://api.deepseek.com/v1/chat/completions"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer sk-34431c6657ca450893e6047d0e26f03d",
        },
        // 构建上下文（最近20条）
        body: () {
          List<Map<String, String>> history = [];

          for (var msg in messages.take(20)) {
            history.add({
              "role": msg["isUser"] ? "user" : "assistant",
              "content": msg["text"],
            });
          }

          history.add({"role": "user", "content": text});

          return jsonEncode({
            "model": useReasoner ? "deepseek-reasoner" : "deepseek-chat",
            "messages": history,
          });
        }(),
      );

      final data = jsonDecode(response.body);
      final reply = data["choices"][0]["message"]["content"];

      setState(() {
        messages.removeLast();
        messages.add({"text": "", "isUser": false});
      });

      for (int i = 0; i < reply.length && isGenerating; i++) {
        await Future.delayed(const Duration(milliseconds: 15));
        setState(() {
          messages.last["text"] += reply[i];
        });
      }

      if (user != null) {
        await supabase.from('messages').insert({
          'user_id': user.id,
          'content': messages.last["text"],
          'is_user': false,
        });
      }

      isGenerating = false;

      scrollToBottom();
    } catch (e) {
      setState(() {
        messages.removeLast();
        messages.add({"text": "请求失败：$e", "isUser": false});
      });
      isGenerating = false;
    }
  }

  void scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text("霜蓝AI"),
        actions: [
          Row(
            children: [
              const Text("深度思考"),
              Switch(
                value: useReasoner,
                onChanged: (v) {
                  setState(() {
                    useReasoner = v;
                  });
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF3F9), Color(0xFFDCEAF5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            if (supabase.auth.currentUser == null)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    const Text(
                      "登录后同步聊天记录",
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: signInWithGoogle,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Image.asset(
                                    'assets/icons/google.png',
                                    width: 18,
                                    height: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Google 登录",
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: signInWithGitHub,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  SvgPicture.asset(
                                    'assets/icons/github.svg',
                                    width: 18,
                                    height: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "GitHub 登录",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final msg = messages[i];
                  final isUser = msg["isUser"];

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.65,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF38BDF8)
                            : Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isUser
                              ? const Radius.circular(16)
                              : Radius.zero,
                          bottomRight: isUser
                              ? Radius.zero
                              : const Radius.circular(16),
                        ),
                      ),
                      child: isUser
                          ? Text(
                              msg["text"],
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            )
                          : MarkdownBody(
                              data: msg["text"],
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                                code: const TextStyle(
                                  backgroundColor: Color(0xFFF1F5F9),
                                  fontFamily: 'monospace',
                                ),
                              ),
                              builders: {'code': CodeElementBuilder()},
                            ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: "有问题，尽管问",
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    isGenerating
                        ? IconButton(
                            icon: const Icon(Icons.stop),
                            color: Colors.red,
                            onPressed: () {
                              setState(() {
                                isGenerating = false;
                              });
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.send),
                            color: const Color(0xFF38BDF8),
                            onPressed: sendMessage,
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(element, TextStyle? preferredStyle) {
    final text = element.textContent;

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: HighlightView(
            text,
            language: 'dart',
            theme: githubTheme,
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        Positioned(
          top: 4,
          right: 6,
          child: GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: text));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                "复制",
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
