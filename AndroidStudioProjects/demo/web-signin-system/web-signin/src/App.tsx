import React, { useState, useEffect } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import io from 'socket.io-client';
import './App.css';

const socket = io('http://localhost:3001');

interface SignInRecord {
  name: string;
  time: string;
  distance: number;
  latitude?: number;
  longitude?: number;
}

// 计算两点之间的距离（米）
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000; // 地球半径（米）
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lon2 - lon1) * Math.PI / 180;

  const a = Math.sin(Δφ/2) * Math.sin(Δφ/2) +
          Math.cos(φ1) * Math.cos(φ2) *
          Math.sin(Δλ/2) * Math.sin(Δλ/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));

  return R * c;
}

function App() {
  const [qrValue, setQrValue] = useState<string>('');
  const [distanceLimit, setDistanceLimit] = useState<number>(100);
  const [signInRecords, setSignInRecords] = useState<SignInRecord[]>([]);
  const [showSettings, setShowSettings] = useState<boolean>(false);
  const [currentLocation, setCurrentLocation] = useState<{latitude: number, longitude: number} | null>(null);

  useEffect(() => {
    socket.on('signIn', (data: SignInRecord) => {
      // 如果签到数据中没有距离信息，计算距离
      if (data.distance === 0 && currentLocation && data.latitude && data.longitude) {
        data.distance = Math.round(calculateDistance(
          currentLocation.latitude,
          currentLocation.longitude,
          data.latitude,
          data.longitude
        ));
      }
      setSignInRecords(prev => [...prev, data]);
    });

    // 获取当前位置
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          setCurrentLocation({
            latitude: position.coords.latitude,
            longitude: position.coords.longitude
          });
        },
        (error) => {
          console.error('获取位置失败:', error);
          alert('无法获取位置信息，请确保已授予位置权限');
        }
      );
    }

    return () => {
      socket.off('signIn');
    };
  }, [currentLocation]);

  const generateQR = () => {
    if (!currentLocation) {
      alert('无法获取位置信息，请确保已授予位置权限');
      return;
    }

    const timestamp = Date.now();
    const data = JSON.stringify({
      timestamp,
      distanceLimit,
      expiresAt: timestamp + 3 * 60 * 60 * 1000, // 3小时后过期
      latitude: currentLocation.latitude,
      longitude: currentLocation.longitude
    });
    setQrValue(data);
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>签到系统</h1>
        <button onClick={() => setShowSettings(true)}>生成签到二维码</button>
        
        {qrValue && (
          <div className="qr-container">
            <QRCodeSVG value={qrValue} size={256} />
            <p>二维码将在3小时后过期</p>
            <p>当前位置: {currentLocation ? `${currentLocation.latitude.toFixed(6)}, ${currentLocation.longitude.toFixed(6)}` : '未获取'}</p>
            <p>距离限制: {distanceLimit} 米</p>
          </div>
        )}

        {showSettings && (
          <div className="settings-modal">
            <h2>设置签到参数</h2>
            <div>
              <label>距离限制（米）：</label>
              <input
                type="number"
                value={distanceLimit}
                onChange={(e) => setDistanceLimit(Number(e.target.value))}
              />
            </div>
            <button onClick={() => {
              generateQR();
              setShowSettings(false);
            }}>确认生成</button>
            <button onClick={() => setShowSettings(false)}>取消</button>
          </div>
        )}

        <div className="records">
          <h2>签到记录</h2>
          <table>
            <thead>
              <tr>
                <th>姓名</th>
                <th>时间</th>
                <th>距离（米）</th>
                <th>位置</th>
              </tr>
            </thead>
            <tbody>
              {signInRecords.map((record, index) => (
                <tr key={index}>
                  <td>{record.name}</td>
                  <td>{record.time}</td>
                  <td>{record.distance}</td>
                  <td>
                    {record.latitude && record.longitude 
                      ? `${record.latitude.toFixed(6)}, ${record.longitude.toFixed(6)}`
                      : '未知'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </header>
    </div>
  );
}

export default App; 