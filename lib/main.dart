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
          pageBuilder: (_, _, _) => const ChatPage(),
          transitionsBuilder: (_, animation, _, child) {
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
            'assets/ailogo.png', // ⚠️ 这里放你的 logo
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
  final TextEditingController emailController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> conversations = [];
  String? currentConversationId;
  bool isGenerating = false;
  List<String> pickedImages = [];
  DateTime? lastEmailSendTime;
  bool isUploadingAvatar = false;

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

  Future<void> loadConversations() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('conversations')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    setState(() {
      conversations = List<Map<String, dynamic>>.from(data);
    });
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

  Future<void> sendMagicLink(String email) async {
    await supabase.auth.signInWithOtp(
      email: email,
      emailRedirectTo: 'io.supabase.flutter://login-callback/',
    );
  }

  @override
  void initState() {
    super.initState();
    _initData();

    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        if (!mounted) return;
        setState(() {});
        loadConversations();
      }
    });
  }

  Future<void> _initData() async {
    await loadConversations();

    if (conversations.isNotEmpty) {
      final convo = conversations.first;
      currentConversationId = convo["id"];

      final msgs = await supabase
          .from('messages')
          .select()
          .eq('conversation_id', currentConversationId!)
          .order('created_at');

      if (!mounted) return;

      setState(() {
        messages = (msgs as List)
            .map((e) => {"text": e['content'], "isUser": e['is_user']})
            .toList();
      });
    }
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
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "输入邮箱",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final email = emailController.text.trim();
                  if (email.isEmpty) return;

                  final now = DateTime.now();
                  if (lastEmailSendTime != null &&
                      now.difference(lastEmailSendTime!).inSeconds < 60) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("请60秒后再试")));
                    return;
                  }

                  lastEmailSendTime = now;

                  await sendMagicLink(email);
                  if (!mounted) return;

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("邮件已发送，请检查收件箱或垃圾邮件")),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Color(0xFF22D3EE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      "发送登录链接",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
      showLoginSheet();
      return; // ⭐ 未登录直接禁止发送
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

    // Insert conversation and user message if needed
    if (currentConversationId == null) {
      final convo = await supabase
          .from('conversations')
          .insert({
            'user_id': user.id,
            'title': text.length > 15 ? text.substring(0, 15) + "..." : text,
          })
          .select()
          .single();

      currentConversationId = convo['id'];
      loadConversations();
    }

    await supabase.from('messages').insert({
      'user_id': user.id,
      'conversation_id': currentConversationId,
      'content': text,
      'is_user': true,
    });

    controller.clear();
    scrollToBottom();

    try {
      final session = supabase.auth.currentSession;
      if (session == null) {
        showLoginSheet();
        return;
      }
      final token = session.accessToken; // ⭐ 必须登录才有 token

      final response = await http.post(
        Uri.parse("https://ai.liuxizekali.workers.dev"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        // 构建上下文（最近20条）
        body: () {
          List<Map<String, String>> history = [];

          for (var msg
              in messages
                  .where(
                    (m) => m["text"] != "思考中..." && m["text"] != "深度思考中...",
                  )
                  .take(20)) {
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

      // Save assistant message
      await supabase.from('messages').insert({
        'user_id': user.id,
        'conversation_id': currentConversationId,
        'content': messages.last["text"],
        'is_user': false,
      });

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
          color: Colors.black.withValues(alpha: 0.05),
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

  Future<void> pickAndUploadAvatar() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      isUploadingAvatar = true;
    });

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      setState(() {
        isUploadingAvatar = false;
      });
      return;
    }

    final file = File(picked.path);
    final fileName = '${user.id}.png';

    // 上传到 Supabase Storage（bucket: avatars）
    await supabase.storage
        .from('avatars')
        .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

    final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

    // 写入用户 metadata
    await supabase.auth.updateUser(
      UserAttributes(data: {'avatar_url': publicUrl}),
    );
    await supabase.auth.refreshSession();
    if (!mounted) return;

    setState(() {
      isUploadingAvatar = false;
    });
  }

  void showUserMenu() {
    final user = supabase.auth.currentUser;

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF22D3EE),
                backgroundImage: (user?.userMetadata?['avatar_url'] != null)
                    ? NetworkImage(user!.userMetadata!['avatar_url'])
                    : null,
                child: (user?.userMetadata?['avatar_url'] == null)
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(user?.email ?? "未登录", style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),

              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text("重新加载对话"),
                onTap: () {
                  Navigator.pop(context);
                  loadConversations();
                },
              ),

              if (user?.userMetadata?['avatar_url'] == null)
                ListTile(
                  leading: const Icon(Icons.image),
                  title: const Text("更换头像"),
                  onTap: () async {
                    Navigator.pop(context);
                    if (isUploadingAvatar) return;

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("头像上传中...")));

                    await pickAndUploadAvatar();
                    if (!mounted) return;

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("头像已更新")));
                  },
                ),

              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text("退出登录"),
                onTap: () async {
                  await supabase.auth.signOut();
                  Navigator.pop(context);
                  setState(() {
                    messages.clear();
                  });
                },
              ),

              const SizedBox(height: 10),
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
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              // 新对话按钮
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text("新对话"),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    currentConversationId = null;
                    messages.clear();
                  });
                },
              ),
              const Text(
                "历史对话",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (_, i) {
                    final convo = conversations[i];

                    return ListTile(
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        onPressed: () async {
                          final id = convo["id"];

                          await supabase
                              .from('messages')
                              .delete()
                              .eq('conversation_id', id);
                          await supabase
                              .from('conversations')
                              .delete()
                              .eq('id', id);

                          loadConversations();

                          if (currentConversationId == id) {
                            if (!mounted) return;
                            setState(() {
                              currentConversationId = null;
                              messages.clear();
                            });
                          }
                        },
                      ),
                      title: Text(
                        convo["title"] ?? "新对话",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        Navigator.pop(context);

                        currentConversationId = convo["id"];

                        final msgs = await supabase
                            .from('messages')
                            .select()
                            .eq('conversation_id', currentConversationId!)
                            .order('created_at');

                        if (!mounted) return;
                        setState(() {
                          messages = (msgs as List)
                              .map(
                                (e) => {
                                  "text": e['content'],
                                  "isUser": e['is_user'],
                                },
                              )
                              .toList();
                        });

                        scrollToBottom();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            );
          },
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
                // Avatar and email clickable row
                return GestureDetector(
                  onTap: showUserMenu,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: const Color(0xFF22D3EE),
                        backgroundImage:
                            (user.userMetadata?['avatar_url'] != null)
                            ? NetworkImage(user.userMetadata!['avatar_url'])
                            : null,
                        child: (user.userMetadata?['avatar_url'] == null)
                            ? const Icon(
                                Icons.person,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        user.email ?? "用户",
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
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
                              : Colors.white.withValues(alpha: 0.95),
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
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
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
                                ? const Color(0xFF22D3EE).withValues(alpha: 0.2)
                                : Colors.black.withValues(alpha: 0.05),
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
                color: Colors.black.withValues(alpha: 0.05),
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
