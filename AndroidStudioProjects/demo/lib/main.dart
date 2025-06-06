import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '签到系统',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? userName;
  late IO.Socket socket;
  bool isScanning = false;
  bool isConnected = false;
  final MobileScannerController controller = MobileScannerController();
  
  // 服务器地址配置
  static const String serverUrl = 'http://10.241.106.22:3001'; 

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _initSocket();
  }

  void _initSocket() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
    });
    
    socket.onConnect((_) {
      print('已连接到服务器');
      setState(() {
        isConnected = true;
      });
      Fluttertoast.showToast(msg: '已连接到服务器');
    });
    
    socket.onDisconnect((_) {
      print('与服务器断开连接');
      setState(() {
        isConnected = false;
      });
      Fluttertoast.showToast(msg: '与服务器断开连接');
    });
    
    socket.onError((error) {
      print('连接错误: $error');
      Fluttertoast.showToast(msg: '连接错误: $error');
    });
    
    socket.onConnectError((error) {
      print('连接错误: $error');
      Fluttertoast.showToast(msg: '连接错误: $error');
    });
    
    socket.connect();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('userName');
    });
  }

  Future<void> _saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', name);
    setState(() {
      userName = name;
    });
  }

  Future<void> _showNameDialog() async {
    String? newName;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('请输入您的姓名'),
        content: TextField(
          onChanged: (value) => newName = value,
          decoration: const InputDecoration(
            hintText: '姓名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (newName != null && newName!.isNotEmpty) {
                _saveUserName(newName!);
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkLocation(double targetLat, double targetLng, double distanceLimit) async {
    try {
      // 首先检查位置服务是否启用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('位置服务未启用');
        Fluttertoast.showToast(msg: '请开启设备的位置服务（GPS）');
        return false;
      }

      // 检查位置权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('位置权限被拒绝');
          Fluttertoast.showToast(msg: '需要位置权限才能签到');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('位置权限被永久拒绝');
        Fluttertoast.showToast(msg: '请在系统设置中允许应用使用位置服务');
        return false;
      }

      // 尝试获取位置，最多重试3次
      Position? position;
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low, // 降低精度要求以加快获取速度
            timeLimit: const Duration(seconds: 5), // 减少超时时间
          );
          break; // 如果成功获取位置，跳出循环
        } catch (e) {
          retryCount++;
          print('获取位置尝试 $retryCount 失败: $e');
          
          if (retryCount < maxRetries) {
            // 等待一段时间后重试
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
          
          // 最后一次尝试失败，尝试获取最后已知位置
          try {
            position = await Geolocator.getLastKnownPosition();
            if (position == null) {
              throw Exception('无法获取位置信息');
            }
          } catch (e) {
            print('获取最后已知位置失败: $e');
            Fluttertoast.showToast(msg: '无法获取位置信息，请检查GPS信号');
            return false;
          }
        }
      }

      if (position == null) {
        print('无法获取位置信息');
        Fluttertoast.showToast(msg: '无法获取位置信息，请检查GPS信号');
        return false;
      }

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        targetLat,
        targetLng,
      );

      print('当前位置: ${position.latitude}, ${position.longitude}');
      print('目标位置: $targetLat, $targetLng');
      print('距离限制: $distanceLimit 米');
      print('实际距离: $distance 米');

      if (distance > distanceLimit) {
        Fluttertoast.showToast(msg: '距离目标位置 ${distance.toStringAsFixed(0)} 米，超出限制');
      }

      return distance <= distanceLimit;
    } catch (e) {
      print('位置检查错误: $e');
      Fluttertoast.showToast(msg: '位置检查失败，请检查GPS是否开启');
      return false;
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (!isScanning) {
      isScanning = true;
      try {
        final List<Barcode> barcodes = capture.barcodes;
        if (barcodes.isEmpty) {
          print('未检测到二维码');
          return;
        }

        final String? code = barcodes.first.rawValue;
        if (code == null) {
          print('二维码内容为空');
          return;
        }

        print('扫描到二维码: $code');
        
        final data = json.decode(code);
        final timestamp = data['timestamp'] as int;
        final distanceLimit = (data['distanceLimit'] as int).toDouble();
        final expiresAt = data['expiresAt'] as int;
        final targetLat = (data['latitude'] ?? 0.0) as double;
        final targetLng = (data['longitude'] ?? 0.0) as double;

        print('二维码数据: $data');

        if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
          print('二维码已过期');
          Fluttertoast.showToast(msg: '二维码已过期');
          return;
        }

        if (userName == null) {
          await _showNameDialog();
          if (userName == null) {
            print('用户未设置姓名');
            Fluttertoast.showToast(msg: '请先设置姓名');
            return;
          }
        }

        final isWithinRange = await _checkLocation(targetLat, targetLng, distanceLimit);
        if (!isWithinRange) {
          print('不在签到范围内');
          Fluttertoast.showToast(msg: '不在签到范围内');
          return;
        }

        if (!isConnected) {
          print('未连接到服务器');
          Fluttertoast.showToast(msg: '未连接到服务器，请检查网络');
          return;
        }

        // 获取当前位置用于计算距离
        Position? position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        );
        
        if (position == null) {
          print('无法获取位置信息');
          Fluttertoast.showToast(msg: '无法获取位置信息');
          return;
        }

        // 计算实际距离
        double actualDistance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          targetLat,
          targetLng,
        );

        final signInData = {
          'name': userName,
          'time': DateTime.now().toString(),
          'distance': actualDistance.round(), // 四舍五入到整数
          'latitude': position.latitude,
          'longitude': position.longitude
        };
        
        print('发送签到数据: $signInData');
        socket.emit('signIn', signInData);
        Fluttertoast.showToast(msg: '签到成功');
      } catch (e) {
        print('二维码处理错误: $e');
        Fluttertoast.showToast(msg: '无效的二维码');
      } finally {
        isScanning = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('签到系统'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: _showNameDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                MobileScanner(
                  controller: controller,
                  onDetect: _onDetect,
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isConnected ? '已连接' : '未连接',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                userName ?? '请点击右上角设置姓名',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    socket.disconnect();
    super.dispose();
  }
}
