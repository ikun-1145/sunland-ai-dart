import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
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
      theme: ThemeData.light(),
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scale = Tween<double>(
      begin: 0.6,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1200), () {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => const ChatPage(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ScaleTransition(
          scale: _scale,
          child: Image.asset(
            'assets/logo.jpg', // ⚠️ 这里放你的 logo
            width: 120,
          ),
        ),
      ),
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
  List<String> pickedImages = [];

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
    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        loadMessages();
      }
    });
  }

  void showLoginSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                "登录霜蓝AI",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                "同步你的聊天记录",
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  signInWithGitHub();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        "assets/icons/github.svg",
                        width: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "使用 GitHub 登录",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  signInWithGoogle();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset("assets/icons/google.png", width: 18),
                      const SizedBox(width: 8),
                      const Text(
                        "使用 Google 登录",
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  "暂不登录",
                  style: TextStyle(color: Colors.black38),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> sendMessage() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      showLoginSheet(); // 仅提示，不拦截
    }
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
        Uri.parse("https://sunlandai.liuxizekali.workers.dev"),
        headers: {"Content-Type": "application/json"},
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

  Widget buildQuickBtn(String text) {
    return GestureDetector(
      onTap: () {
        controller.text = text.replaceAll(
          RegExp(r'^[^ ]+ '),
          '',
        ); // 去掉 emoji 前缀
        sendMessage();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Future<void> pickImage() async {
    // 📱 移动端：使用 image_picker
    if (Platform.isAndroid || Platform.isIOS) {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage();

      if (picked.isEmpty) return;

      setState(() {
        for (var img in picked) {
          pickedImages.add(img.path);
        }
      });
      return;
    }

    // 💻 桌面端：使用 file_picker
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (var file in result.files) {
        if (file.path != null) {
          pickedImages.add(file.path!);
        }
      }
    });
  }

  void showUserMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text("退出登录"),
                onTap: () async {
                  await supabase.auth.signOut();
                  Navigator.pop(context);
                  setState(() {
                    messages.clear();
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("霜蓝AI"),
            Builder(
              builder: (_) {
                final user = supabase.auth.currentUser;
                if (user == null) {
                  return GestureDetector(
                    onTap: showLoginSheet,
                    child: const Text("登录", style: TextStyle(fontSize: 14)),
                  );
                }
                return Row(
                  children: [
                    const Icon(Icons.account_circle, size: 20),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: showUserMenu,
                      child: const Text("已登录", style: TextStyle(fontSize: 14)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // 背景渐变（更高级）
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF3F8FF), Color(0xFFE6F2FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          Column(
            children: [
              const SizedBox(height: 80),

              // 欢迎区（仿 Gemini）
              if (messages.where((m) => m["isUser"] == true).isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        "霜蓝，你好",
                        style: TextStyle(fontSize: 20, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        "需要我为你做些什么？",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 快捷按钮
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        buildQuickBtn("🧠 激发我的活力"),
                        buildQuickBtn("✨ 给我一点灵感"),
                        buildQuickBtn("📄 随便聊聊"),
                      ],
                    ),
                  ],
                ),

              // 聊天区
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
                              ? const Color(0xFF22D3EE)
                              : Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(18),
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
                                builders: {'code': CodeElementBuilder()},
                              ),
                      ),
                    );
                  },
                ),
              ),

              // 输入框（更像 Gemini）
              SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: pickImage,
                        child: const Icon(Icons.add, color: Colors.grey),
                      ),

                      const SizedBox(width: 6),

                      if (pickedImages.isNotEmpty)
                        SizedBox(
                          height: 40,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: pickedImages.length,
                            itemBuilder: (_, i) {
                              return Container(
                                margin: const EdgeInsets.only(right: 6),
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        File(pickedImages[i]),
                                        fit: BoxFit.cover,
                                        width: 40,
                                        height: 40,
                                      ),
                                    ),

                                    Positioned(
                                      top: -4,
                                      right: -4,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            pickedImages.removeAt(i);
                                          });
                                        },
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(width: 6),

                      GestureDetector(
                        onTap: () {
                          setState(() {
                            useReasoner = !useReasoner;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: useReasoner
                                ? const Color(0xFF22D3EE).withOpacity(0.2)
                                : Colors.black.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: useReasoner
                                  ? const Color(0xFF22D3EE)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: useReasoner
                                ? const Color(0xFF22D3EE)
                                : Colors.black54,
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            hintText: "问点什么...",
                            border: InputBorder.none,
                          ),
                        ),
                      ),

                      IconButton(
                        icon: const Icon(Icons.send),
                        color: const Color(0xFF22D3EE),
                        onPressed: sendMessage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
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
