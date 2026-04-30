import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';

const bool debugMode = true;

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

class ResendEmailAuthApi {
  const ResendEmailAuthApi({
    this.requestCodeEndpoint = 'https://your-api.example.com/auth/email/code',
    this.verifyCodeEndpoint = 'https://your-api.example.com/auth/email/verify',
  });

  final String requestCodeEndpoint;
  final String verifyCodeEndpoint;

  Future<void> requestCode(String email) async {
    final response = await http.post(
      Uri.parse(requestCodeEndpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('验证码发送失败: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> verifyCode({
    required String email,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse(verifyCodeEndpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('验证码校验失败: ${response.statusCode}');
    }

    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
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
  Timer? _splashTimer;

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

    _splashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
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
    _splashTimer?.cancel();
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
  final ScrollController scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> conversations = [];
  final Map<String, List<Map<String, dynamic>>> localConversationMessages = {};
  String? currentConversationId;
  bool isGenerating = false;
  List<String> pickedImages = [];
  bool isUploadingAvatar = false;

  String buildConversationTitle(String text) {
    return text.length > 15 ? "${text.substring(0, 15)}..." : text;
  }

  bool isLocalConversation(String? id) => id?.startsWith('local_') ?? false;

  void rememberLocalMessages() {
    final id = currentConversationId;
    if (id == null || !isLocalConversation(id)) return;

    localConversationMessages[id] = messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
  }

  void createLocalConversation(String firstMessage) {
    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    currentConversationId = id;
    conversations.insert(0, {
      'id': id,
      'title': buildConversationTitle(firstMessage),
      'is_local': true,
    });
  }

  Future<void> loadMessages() async {
    final user = debugMode ? null : supabase.auth.currentUser;
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
    final user = debugMode ? null : supabase.auth.currentUser;
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

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void showProfileSetupDialog() {
    final nameController = TextEditingController();
    String? avatarPath;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("完善资料"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked != null) {
                        setStateDialog(() {
                          avatarPath = picked.path;
                        });
                      }
                    },
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF22D3EE),
                      backgroundImage: avatarPath != null
                          ? FileImage(File(avatarPath!))
                          : null,
                      child: avatarPath == null
                          ? const Icon(Icons.camera_alt, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      hintText: "输入昵称",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final user = supabase.auth.currentUser;
                    if (user == null) return;

                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text("请输入昵称")));
                      return;
                    }

                    String? avatarUrl;

                    if (avatarPath != null) {
                      final file = File(avatarPath!);
                      final fileName = '${user.id}.png';

                      await supabase.storage
                          .from('avatars')
                          .upload(
                            fileName,
                            file,
                            fileOptions: const FileOptions(upsert: true),
                          );

                      avatarUrl = supabase.storage
                          .from('avatars')
                          .getPublicUrl(fileName);
                    }

                    await supabase.auth.updateUser(
                      UserAttributes(
                        data: {'name': name, 'avatar_url': avatarUrl},
                      ),
                    );

                    await supabase.auth.refreshSession();

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    if (!mounted) return;
                    setState(() {});
                  },
                  child: const Text("保存"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _initData() async {
    if (debugMode) return;
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

  Future<void> sendMessage() async {
    if (isGenerating) return; // 防止重复发送
    final user = debugMode ? null : supabase.auth.currentUser;
    final text = controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      isGenerating = true;
    });

    setState(() {
      messages.add({"text": text, "isUser": true});
      messages.add({
        "text": useReasoner ? "深度思考中..." : "思考中...",
        "isUser": false,
      });
    });

    // Insert conversation and user message if needed
    if (currentConversationId == null) {
      if (user != null) {
        final convo = await supabase
            .from('conversations')
            .insert({'user_id': user.id, 'title': buildConversationTitle(text)})
            .select()
            .single();

        currentConversationId = convo['id'];
        loadConversations();
      } else {
        setState(() {
          createLocalConversation(text);
        });
      }
    }

    if (user != null) {
      await supabase.from('messages').insert({
        'user_id': user.id,
        'conversation_id': currentConversationId,
        'content': text,
        'is_user': true,
      });
    } else {
      rememberLocalMessages();
    }

    controller.clear();
    scrollToBottom();

    try {
      final session = supabase.auth.currentSession;
      final headers = <String, String>{
        "Content-Type": "application/json",
        if (session != null) "Authorization": "Bearer ${session.accessToken}",
      };

      // ===== 构建上下文 =====
      List<Map<String, String>> history = [];

      // Build message history (block replaced)
      final validMessages = messages
          .where((m) => m["text"] != "思考中..." && m["text"] != "深度思考中...")
          .toList();

      final lastMessages = validMessages.length > 20
          ? validMessages.sublist(validMessages.length - 20)
          : validMessages;

      for (var msg in lastMessages) {
        history.add({
          "role": msg["isUser"] ? "user" : "assistant",
          "content": msg["text"],
        });
      }

      // ===== 图片转 base64 加入 =====
      for (var path in pickedImages) {
        final bytes = await File(path).readAsBytes();
        final base64Img = base64Encode(bytes);

        history.add({
          "role": "user",
          "content": "![image](data:image/png;base64,$base64Img)",
        });
      }

      // 清空已选图片
      if (pickedImages.isNotEmpty) {
        setState(() {
          pickedImages.clear();
        });
      }

      // http.post with timeout
      final response = await http
          .post(
            Uri.parse("https://ai.liuxizekali.workers.dev"),
            headers: headers,
            body: jsonEncode({
              "model": useReasoner ? "deepseek-reasoner" : "deepseek-chat",
              "messages": history,
            }),
          )
          .timeout(const Duration(seconds: 20));

      // Status code check
      if (response.statusCode != 200) {
        throw Exception("服务器错误: ${response.statusCode}");
      }

      // Robust JSON decode
      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (e) {
        throw Exception("返回数据解析失败");
      }

      // Safer extraction of reply/reasoning
      if (data == null || data["choices"] == null || data["choices"].isEmpty) {
        throw Exception("返回数据异常");
      }

      final messageData = data["choices"][0]["message"];
      final reply = messageData["content"] ?? "";
      final reasoning =
          messageData["reasoning_content"] ?? messageData["reasoning"];

      setState(() {
        messages.removeLast();

        if (reasoning != null && reasoning.toString().isNotEmpty) {
          messages.add({
            "text": reasoning,
            "isUser": false,
            "isReasoning": true,
            "expanded": false,
          });
        }

        messages.add({"text": "", "isUser": false});
      });

      for (int i = 0; i < reply.length && isGenerating; i++) {
        await Future.delayed(const Duration(milliseconds: 15));
        setState(() {
          messages.last["text"] += reply[i];
        });
        if (i % 10 == 0) scrollToBottom();
      }

      if (user != null) {
        // Save assistant message
        await supabase.from('messages').insert({
          'user_id': user.id,
          'conversation_id': currentConversationId,
          'content': messages.last["text"],
          'is_user': false,
        });
      } else {
        rememberLocalMessages();
      }

      setState(() {
        isGenerating = false;
      });
      scrollToBottom();
    } catch (e) {
      setState(() {
        messages.removeLast();
        messages.add({"text": "请求失败：$e", "isUser": false});
        isGenerating = false;
      });
      rememberLocalMessages();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
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
    final user = debugMode ? null : supabase.auth.currentUser;
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
    final user = debugMode ? null : supabase.auth.currentUser;

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
              Text(
                user?.email ?? "开发模式（免登录）",
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),

              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(user == null ? "保留本地对话" : "重新加载对话"),
                onTap: () {
                  Navigator.pop(context);
                  if (user != null) loadConversations();
                },
              ),

              if (user != null && user.userMetadata?['avatar_url'] == null)
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
                    if (!context.mounted) return;
                    if (!mounted) return;

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("头像已更新")));
                  },
                ),

              if (user != null)
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text("退出登录"),
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    await supabase.auth.signOut();
                    navigator.pop();
                    if (!mounted) return;
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
        backgroundColor: const Color(0xFF0F0F0F),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo + 标题
                Row(
                  children: const [
                    Icon(Icons.auto_awesome, color: Color(0xFFFF8A3D)),
                    SizedBox(width: 8),
                    Text(
                      "霜蓝 AI",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 新建对话按钮（Claude 风格）
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      currentConversationId = null;
                      messages.clear();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.white70, size: 18),
                          SizedBox(width: 6),
                          Text("新建对话", style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // 底部用户（弱化版）
                Row(
                  children: const [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black,
                      child: Text("刘", style: TextStyle(color: Colors.white)),
                    ),
                    SizedBox(width: 10),
                    Text("刘锡泽", style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ],
            ),
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
                final user = debugMode ? null : supabase.auth.currentUser;
                // Avatar and email clickable row
                return GestureDetector(
                  onTap: showUserMenu,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: const Color(0xFF22D3EE),
                        backgroundImage:
                            (user?.userMetadata?['avatar_url'] != null)
                            ? NetworkImage(user!.userMetadata!['avatar_url'])
                            : null,
                        child: (user?.userMetadata?['avatar_url'] == null)
                            ? const Icon(
                                Icons.person,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        user?.userMetadata?['name'] ??
                            user?.email?.split('@')[0] ??
                            "开发模式",
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
                Builder(
                  builder: (_) {
                    final user = debugMode ? null : supabase.auth.currentUser;
                    final displayName =
                        user?.userMetadata?['name'] ??
                        user?.email?.split('@')[0];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: Text(
                            displayName != null ? "$displayName 👋" : "你好 👋",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: ShaderMask(
                            shaderCallback: (bounds) {
                              return const LinearGradient(
                                colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
                              ).createShader(bounds);
                            },
                            child: const Text(
                              "今天想做点什么？",
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              buildQuickBtn("🧠 激发我的活力"),
                              buildQuickBtn("✨ 给我一点灵感"),
                              buildQuickBtn("📄 随便聊聊"),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
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
                            : (msg["isReasoning"] == true
                                  ? GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          msg["expanded"] =
                                              !(msg["expanded"] ?? false);
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.psychology,
                                                  size: 16,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 6),
                                                const Text(
                                                  "思考过程",
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (msg["expanded"] == true) ...[
                                              const SizedBox(height: 6),
                                              MarkdownBody(
                                                data: msg["text"],
                                                selectable: true,
                                                builders: {
                                                  'code': CodeElementBuilder(),
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    )
                                  : MarkdownBody(
                                      data: msg["text"],
                                      selectable: true,
                                      builders: {'code': CodeElementBuilder()},
                                    )),
                      ),
                    );
                  },
                ),
              ),

              // 输入框（更像 Gemini）
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFF22D3EE).withValues(alpha: 0.15),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: pickImage,
                          child: AnimatedScale(
                            scale: isGenerating ? 0.9 : 1,
                            duration: const Duration(milliseconds: 120),
                            child: const Icon(Icons.add, color: Colors.grey),
                          ),
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
                          child: AnimatedScale(
                            scale: useReasoner ? 1.05 : 1,
                            duration: const Duration(milliseconds: 120),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: useReasoner
                                    ? const Color(
                                        0xFF22D3EE,
                                      ).withValues(alpha: 0.2)
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
                        ),

                        const SizedBox(width: 6),

                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            child: TextField(
                              controller: controller,
                              enabled: !isGenerating,
                              decoration: const InputDecoration(
                                hintText: "问点什么...",
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),

                        IconButton(
                          icon: isGenerating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF22D3EE),
                                  ),
                                )
                              : const Icon(Icons.send),
                          color: isGenerating
                              ? Colors.grey
                              : const Color(0xFF22D3EE),
                          onPressed: isGenerating ? null : sendMessage,
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
            language: 'plaintext',
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
