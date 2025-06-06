const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*", // 允许所有来源访问，生产环境应该限制为特定域名
    methods: ["GET", "POST"]
  },
  pingTimeout: 60000,
  pingInterval: 25000,
});

// 存储连接的客户端
const connectedClients = new Set();

io.on('connection', (socket) => {
  console.log(`用户已连接: ${socket.id}`);
  connectedClients.add(socket.id);

  // 发送当前连接状态
  io.emit('connectionStatus', {
    type: 'connect',
    clientId: socket.id,
    totalClients: connectedClients.size
  });

  socket.on('signIn', (data) => {
    console.log('收到签到数据:', data);
    
    // 添加时间戳和客户端ID
    const signInData = {
      ...data,
      clientId: socket.id,
      serverTime: new Date().toISOString()
    };

    // 广播签到信息给所有连接的客户端
    io.emit('signIn', signInData);
    console.log('已广播签到数据');
  });

  socket.on('disconnect', () => {
    console.log(`用户已断开连接: ${socket.id}`);
    connectedClients.delete(socket.id);
    
    // 广播断开连接状态
    io.emit('connectionStatus', {
      type: 'disconnect',
      clientId: socket.id,
      totalClients: connectedClients.size
    });
  });

  socket.on('error', (error) => {
    console.error(`Socket错误: ${socket.id}`, error);
  });
});

// 错误处理
server.on('error', (error) => {
  console.error('服务器错误:', error);
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`服务器运行在端口 ${PORT}`);
  console.log(`允许的CORS来源: ${io._opts.cors.origin}`);
}); 