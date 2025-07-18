#include <Arduino.h>
#include <SparkFun_u-blox_GNSS_Arduino_Library.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <Wire.h>
#include <SparkFun_MAX1704x_Fuel_Gauge_Arduino_Library.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <FS.h>
#include <SD_MMC.h>
#include <SPI.h>
#include <Preferences.h>
#include <FastLED.h>
#include <U8g2lib.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

// FastLED Configuration for built-in WS2812
#define LED_PIN 46        // Pin 46 on Thing Plus C S3 is connected to WS2812 LED
#define COLOR_ORDER GRB
#define CHIPSET WS2812
#define NUM_LEDS 1
#define BRIGHTNESS 25
CRGB leds[NUM_LEDS];

// BLE Service and Characteristic UUIDs
const char* telemetryServiceUUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
const char* telemetryCharUUID    = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
const char* configCharUUID       = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
const char* fileTransferCharUUID = "6e400005-b5a3-f393-e0a9-e50e24dcca9e";

// Hardware Configuration
SFE_MAX1704X lipo;
SFE_UBLOX_GNSS myGNSS;
Adafruit_MPU6050 mpu;
Preferences preferences;
// SH1106 OLED display (I2C)
U8G2_SH1106_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE);

// Pin Definitions for ESP32-S3 Thing Plus
#define GNSS_RX 4
#define GNSS_TX 2
#define SD_DETECT 48
#define BUTTON_A_PIN 6

HardwareSerial GNSS_Serial(2);

// Button handling - SUPER SIMPLE
bool lastButtonState = HIGH;
bool buttonPressed = false;
unsigned long lastDisplayUpdate = 0;
bool displayNeedsUpdate = true;

// MPU6050 variables
struct IMUData {
  float accelX, accelY, accelZ;       // Accelerometer (g)
  float gyroX, gyroY, gyroZ;          // Gyroscope (deg/s)
  float temperature;                   // Temperature (°C)
  float magnitude;                     // Total acceleration magnitude
  bool motionDetected = false;         // Motion detection flag
  unsigned long lastMotionTime = 0;    // Last motion detection time
} imuData;

bool mpuAvailable = false;
const float MOTION_THRESHOLD = 1.2;   // g-force threshold for motion detection
const float IMPACT_THRESHOLD = 2.5;   // g-force threshold for impact detection

// SDIO pins for ESP32-S3 Thing Plus
int pin_sdioCLK = 38;
int pin_sdioCMD = 34;
int pin_sdioD0 = 39;
int pin_sdioD1 = 40;
int pin_sdioD2 = 47;
int pin_sdioD3 = 33;

// WiFi Configuration
const char* ssid = "Puchatkova";
const char* password = "Internet2@";
const IPAddress remoteIP(172, 16, 2, 158);
const uint16_t remotePort = 9000;
WiFiUDP udp;

// BLE Configuration
BLECharacteristic* telemetryChar = nullptr;
BLECharacteristic* configChar = nullptr;
BLECharacteristic* fileTransferChar = nullptr;
BLE2902* telemetryDescriptor = nullptr;

// SD Card and Logging
File logFile;
bool sdCardAvailable = false;
bool loggingActive = false;
char currentLogFilename[64] = "";

// File Transfer State
struct FileTransferState {
  bool active = false;
  File transferFile;
  String filename = "";
  size_t fileSize = 0;
  size_t bytesSent = 0;
  unsigned long lastChunkTime = 0;
  bool listingFiles = false;
} fileTransfer;

// LED Status Management
enum LEDStatus {
  LED_STARTUP,
  LED_NO_GPS,
  LED_GPS_SEARCHING,
  LED_GPS_GOOD,
  LED_LOGGING,
  LED_ERROR,
  LED_LOW_BATTERY,
  LED_FILE_TRANSFER,
  LED_BLE_CONNECTED
};

LEDStatus currentLEDStatus = LED_STARTUP;
unsigned long lastLEDUpdate = 0;
uint8_t ledBrightness = 0;
bool ledDirection = true;

// Enhanced Performance Monitoring
struct PerformanceStats {
  unsigned long totalPackets = 0;
  unsigned long droppedPackets = 0;
  unsigned long sequenceErrors = 0;
  unsigned long minDelta = 9999;
  unsigned long maxDelta = 0;
  unsigned long avgDelta = 0;
  float memoryUsage = 0.0f;
  unsigned long lastResetTime = 0;
} perfStats;

// GPS Packet Structure (40 bytes total: 38 payload + 2 CRC) - Extended for IMU
struct __attribute__((packed)) GPSPacket {
  uint32_t timestamp;      // Unix epoch (4 bytes)
  int32_t latitude;        // deg * 1e7 (4 bytes)
  int32_t longitude;       // deg * 1e7 (4 bytes)
  int32_t altitude;        // mm (4 bytes)
  uint16_t speed;          // mm/s (2 bytes)
  uint32_t heading;        // deg * 1e5 (4 bytes)
  uint8_t fixType;         // 0-5 (1 byte)
  uint8_t satellites;      // count (1 byte)
  uint16_t battery_mv;     // mV (2 bytes)
  uint8_t battery_pct;     // % (1 byte)
  
  // IMU data (10 bytes)
  int16_t accel_x;         // mg (2 bytes)
  int16_t accel_y;         // mg (2 bytes) 
  int16_t accel_z;         // mg (2 bytes)
  int16_t gyro_x;          // deg/s * 100 (2 bytes)
  int16_t gyro_y;          // deg/s * 100 (2 bytes)
  
  uint8_t reserved1;       // padding (1 byte) - Total payload: 38 bytes
  uint16_t crc;            // CRC16 (2 bytes) - Total: 40 bytes
};

uint32_t packetSequence = 0;
unsigned long lastMotionTime = 0;

// MPU6xxx Direct I2C Functions
#define MPU6xxx_ADDRESS 0x68
#define MPU6xxx_WHO_AM_I 0x75
#define MPU6xxx_PWR_MGMT_1 0x6B
#define MPU6xxx_ACCEL_XOUT_H 0x3B
#define MPU6xxx_GYRO_XOUT_H 0x43
#define MPU6xxx_TEMP_OUT_H 0x41
#define MPU6xxx_ACCEL_CONFIG 0x1C
#define MPU6xxx_GYRO_CONFIG 0x1B

void writeRegister(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(MPU6xxx_ADDRESS);
  Wire.write(reg);
  Wire.write(value);
  Wire.endTransmission();
}

uint8_t readRegister(uint8_t reg) {
  Wire.beginTransmission(MPU6xxx_ADDRESS);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU6xxx_ADDRESS, 1, true);
  return Wire.read();
}

int16_t readRegister16(uint8_t reg) {
  Wire.beginTransmission(MPU6xxx_ADDRESS);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU6xxx_ADDRESS, 2, true);
  int16_t value = Wire.read() << 8;
  value |= Wire.read();
  return value;
}

bool initMPU6050() {
  Serial.println("🔄 Initializing IMU...");
  
  delay(100);
  
  // Read WHO_AM_I register
  uint8_t whoami = readRegister(MPU6xxx_WHO_AM_I);
  Serial.printf("📋 WHO_AM_I register: 0x%02X\n", whoami);
  
  // Check for different IMU types
  switch (whoami) {
    case 0x68:
      Serial.println("✅ Detected: MPU6050");
      break;
    case 0x70:
      Serial.println("✅ Detected: MPU6000 or MPU9250");
      break;
    case 0x71:
      Serial.println("✅ Detected: MPU9250");
      break;
    case 0x73:
      Serial.println("✅ Detected: MPU9255");
      break;
    default:
      Serial.printf("⚠️ Unknown IMU type: 0x%02X (trying anyway...)\n", whoami);
      break;
  }
  
  // Wake up the MPU6xxx (it starts in sleep mode)
  writeRegister(MPU6xxx_PWR_MGMT_1, 0x00);
  delay(100);
  Serial.println("✅ MPU woken up from sleep mode");
  
  // Set accelerometer range to ±2g (0x00)
  writeRegister(MPU6xxx_ACCEL_CONFIG, 0x00);
  Serial.println("✅ Accelerometer range set to ±2g");
  
  // Set gyroscope range to ±250°/s (0x00)
  writeRegister(MPU6xxx_GYRO_CONFIG, 0x00);
  Serial.println("✅ Gyroscope range set to ±250°/s");
  
  // Test read to make sure everything works
  int16_t accelX = readRegister16(MPU6xxx_ACCEL_XOUT_H);
  int16_t accelY = readRegister16(MPU6xxx_ACCEL_XOUT_H + 2);
  int16_t accelZ = readRegister16(MPU6xxx_ACCEL_XOUT_H + 4);
  int16_t temp = readRegister16(MPU6xxx_TEMP_OUT_H);
  
  // Convert to real units
  float accelX_g = accelX / 16384.0;  // ±2g range
  float accelY_g = accelY / 16384.0;
  float accelZ_g = accelZ / 16384.0;
  
  // Temperature formula depends on chip type
  float temp_c;
  if (whoami == 0x68) {
    // MPU6050 formula
    temp_c = (temp / 340.0) + 36.53;
  } else {
    // MPU6000/9250 formula  
    temp_c = (temp / 333.87) + 21.0;
  }
  
  Serial.printf("✅ Test read successful:\n");
  Serial.printf("   Accel: %.2f, %.2f, %.2f g\n", accelX_g, accelY_g, accelZ_g);
  Serial.printf("   Temperature: %.1f°C\n", temp_c);
  
  mpuAvailable = true;
  Serial.println("✅ IMU configured successfully using direct I2C");
  return true;
}

void readMPU6050() {
  if (!mpuAvailable) return;
  
  // Read accelerometer data
  int16_t accelX = readRegister16(MPU6xxx_ACCEL_XOUT_H);
  int16_t accelY = readRegister16(MPU6xxx_ACCEL_XOUT_H + 2);
  int16_t accelZ = readRegister16(MPU6xxx_ACCEL_XOUT_H + 4);
  
  // Read gyroscope data
  int16_t gyroX = readRegister16(MPU6xxx_GYRO_XOUT_H);
  int16_t gyroY = readRegister16(MPU6xxx_GYRO_XOUT_H + 2);
  int16_t gyroZ = readRegister16(MPU6xxx_GYRO_XOUT_H + 4);
  
  // Read temperature
  int16_t temp = readRegister16(MPU6xxx_TEMP_OUT_H);
  
  // Convert to real units
  imuData.accelX = accelX / 16384.0;  // ±2g range
  imuData.accelY = accelY / 16384.0;
  imuData.accelZ = accelZ / 16384.0;
  
  imuData.gyroX = gyroX / 131.0;      // ±250°/s range
  imuData.gyroY = gyroY / 131.0;
  imuData.gyroZ = gyroZ / 131.0;
  
  // Temperature formula - get WHO_AM_I to determine chip type
  static uint8_t chipType = 0;
  if (chipType == 0) {
    chipType = readRegister(MPU6xxx_WHO_AM_I);
  }
  
  if (chipType == 0x68) {
    // MPU6050 formula
    imuData.temperature = (temp / 340.0) + 36.53;
  } else {
    // MPU6000/9250/9255 formula
    imuData.temperature = (temp / 333.87) + 21.0;
  }
  
  // Calculate total acceleration magnitude
  imuData.magnitude = sqrt(imuData.accelX * imuData.accelX + 
                          imuData.accelY * imuData.accelY + 
                          imuData.accelZ * imuData.accelZ);
  
  // Motion detection
  if (imuData.magnitude > MOTION_THRESHOLD) {
    if (!imuData.motionDetected) {
      Serial.printf("🏃 Motion detected! Magnitude: %.2fg\n", imuData.magnitude);
    }
    imuData.motionDetected = true;
    imuData.lastMotionTime = millis();
  } else {
    // Clear motion flag after 2 seconds of no motion
    if (imuData.motionDetected && (millis() - imuData.lastMotionTime > 2000)) {
      imuData.motionDetected = false;
      Serial.println("😴 Motion stopped");
    }
  }
  
  // Impact detection
  if (imuData.magnitude > IMPACT_THRESHOLD) {
    Serial.printf("💥 IMPACT DETECTED! Magnitude: %.2fg\n", imuData.magnitude);
    // Could trigger automatic logging here
  }
}
void processButtons() {
  bool currentButtonState = digitalRead(BUTTON_A_PIN);
  
  // Simple logic: if button goes from HIGH to LOW, toggle recording
  if (currentButtonState == LOW && lastButtonState == HIGH) {
    Serial.println("🎮 BUTTON PRESSED! Toggling recording...");
    toggleLogging();
    displayNeedsUpdate = true;
    delay(200); // Simple debounce - just wait 200ms
  }
  
  lastButtonState = currentButtonState;
}

void toggleLogging() {
  Serial.printf("🎮 toggleLogging() START - Current state: %s\n", loggingActive ? "ON" : "OFF");
  Serial.printf("🎮 Pre-check - SD Available: %s, GPS Fix Type: %d\n", 
                sdCardAvailable ? "YES" : "NO", myGNSS.getFixType());
  
  if (loggingActive) {
    Serial.println("🎮 Stopping logging...");
    loggingActive = false;
    if (logFile) {
      logFile.close();
      Serial.println("⚪ Logging stopped by button");
    }
    if (myGNSS.getFixType() >= 3) {
      setLEDStatus(LED_GPS_GOOD);
    } else {
      setLEDStatus(LED_GPS_SEARCHING);
    }
  } else {
    Serial.println("🎮 Attempting to start logging...");
    if (sdCardAvailable && myGNSS.getFixType() >= 2) {
      Serial.println("🎮 Conditions met, starting logging...");
      loggingActive = true;
      bool fileCreated = createLogFile();
      if (fileCreated) {
        setLEDStatus(LED_LOGGING);
        Serial.println("🔴 Logging started by button");
      } else {
        loggingActive = false;
        Serial.println("❌ Failed to create log file, logging disabled");
      }
    } else {
      Serial.printf("❌ Cannot start logging - SD: %s, GPS Fix: %d (need >=2)\n", 
                    sdCardAvailable ? "OK" : "NO", myGNSS.getFixType());
    }
  }
  Serial.printf("🎮 toggleLogging() END - New state: %s\n", loggingActive ? "ON" : "OFF");
}

// Single Screen Display Function
void updateDisplay() {
  // Update display every 1 second or when requested
  if (!displayNeedsUpdate && (millis() - lastDisplayUpdate < 1000)) return;
  
  Serial.println("📺 Updating main display...");
  
  u8g2.clearBuffer();
  
  // Title
  u8g2.setFont(u8g2_font_6x10_tr);
  u8g2.drawStr(0, 10, "GPS Logger v2.2");
  
  // Battery Status (Top Right)
  u8g2.setFont(u8g2_font_5x7_tr);
  float batteryVoltage = lipo.getVoltage();
  float batteryPercent = lipo.getSOC();
  char battStr[32];
  sprintf(battStr, "%.1fV %d%%", batteryVoltage, (int)batteryPercent);
  u8g2.drawStr(70, 10, battStr);
  
  // Date and Time
  u8g2.setFont(u8g2_font_5x7_tr);
  char dateTimeStr[32];
  if (myGNSS.getFixType() >= 2) {
    sprintf(dateTimeStr, "%02d/%02d/%04d %02d:%02d:%02d", 
            myGNSS.getDay(), myGNSS.getMonth(), myGNSS.getYear(),
            myGNSS.getHour(), myGNSS.getMinute(), myGNSS.getSecond());
  } else {
    sprintf(dateTimeStr, "No GPS Time");
  }
  u8g2.drawStr(0, 22, dateTimeStr);
  
  // GPS Status and Satellites
  char gpsStr[32];
  uint8_t fixType = myGNSS.getFixType();
  uint8_t satellites = myGNSS.getSIV();
  const char* fixNames[] = {"No Fix", "Dead Rec", "2D Fix", "3D Fix", "GNSS+DR", "Time Only"};
  const char* fixName = (fixType <= 5) ? fixNames[fixType] : "Unknown";
  sprintf(gpsStr, "%s - %d sats", fixName, satellites);
  u8g2.drawStr(0, 34, gpsStr);
  
  // Current Speed and Motion Status
  u8g2.setFont(u8g2_font_6x10_tr);
  float speed_kmh = myGNSS.getGroundSpeed() * 0.0036f;
  char speedStr[32];
  if (mpuAvailable && imuData.motionDetected) {
    sprintf(speedStr, "Speed: %.1f km/h M", speed_kmh); // M = Motion
  } else {
    sprintf(speedStr, "Speed: %.1f km/h", speed_kmh);
  }
  u8g2.drawStr(0, 46, speedStr);
  
  // IMU Data (if available)
  u8g2.setFont(u8g2_font_5x7_tr);
  if (mpuAvailable) {
    char imuStr[32];
    sprintf(imuStr, "G: %.1fg T: %.0fC", imuData.magnitude, imuData.temperature);
    u8g2.drawStr(0, 55, imuStr);
  }
  
  // SD Card and Recording Status
  u8g2.setFont(u8g2_font_5x7_tr);
  char statusStr[64];
  if (!sdCardAvailable) {
    sprintf(statusStr, "SD: NO CARD");
  } else if (loggingActive) {
    sprintf(statusStr, "REC: LOGGING [%lu]", perfStats.totalPackets);
  } else {
    sprintf(statusStr, "REC: READY (Press A)");
  }
  u8g2.drawStr(0, 64, statusStr);
  
  u8g2.sendBuffer();
  displayNeedsUpdate = false;
  lastDisplayUpdate = millis();
  
  Serial.printf("✅ Display updated - GPS: %s, Speed: %.1f km/h, Recording: %s\n", 
                fixName, speed_kmh, loggingActive ? "ON" : "OFF");
  if (mpuAvailable) {
    Serial.printf("   IMU: %.1fg, Motion: %s, Temp: %.1f°C\n", 
                  imuData.magnitude, imuData.motionDetected ? "YES" : "NO", imuData.temperature);
  }
}

// LED Control Functions
void initLED() {
  FastLED.addLeds<CHIPSET, LED_PIN, COLOR_ORDER>(leds, NUM_LEDS).setCorrection(TypicalLEDStrip);
  FastLED.setBrightness(BRIGHTNESS);
  FastLED.clear();
  FastLED.show();
  Serial.println("💡 WS2812 LED initialized");
}

void setLEDStatus(LEDStatus status) {
  currentLEDStatus = status;
  lastLEDUpdate = millis();
}

void updateLED() {
  unsigned long now = millis();
  
  // Update LED every 50ms for smooth animations
  if (now - lastLEDUpdate < 50) return;
  lastLEDUpdate = now;
  
  switch (currentLEDStatus) {
    case LED_STARTUP:
      // Purple breathing effect during startup
      if (ledDirection) {
        ledBrightness += 5;
        if (ledBrightness >= 255) {
          ledBrightness = 255;
          ledDirection = false;
        }
      } else {
        ledBrightness -= 5;
        if (ledBrightness <= 0) {
          ledBrightness = 0;
          ledDirection = true;
        }
      }
      leds[0] = CRGB(ledBrightness, 0, ledBrightness); // Purple
      break;
      
    case LED_NO_GPS:
      // Red blinking - no GPS module
      leds[0] = ((now / 500) % 2) ? CRGB::Red : CRGB::Black;
      break;
      
    case LED_GPS_SEARCHING:
      // Orange blinking - searching for satellites
      leds[0] = ((now / 1000) % 2) ? CRGB::Orange : CRGB::Black;
      break;
      
    case LED_GPS_GOOD:
      // Green solid - good GPS fix
      leds[0] = CRGB::Green;
      break;
      
    case LED_LOGGING:
      // Blue fast blinking - logging active
      leds[0] = ((now / 200) % 2) ? CRGB::White : CRGB::Green;
      break;
      
    case LED_ERROR:
      // Red fast blinking - error state
      leds[0] = ((now / 100) % 2) ? CRGB::Red : CRGB::Black;
      break;
      
    case LED_LOW_BATTERY:
      // Yellow slow blinking - low battery
      leds[0] = ((now / 2000) % 2) ? CRGB::Yellow : CRGB::Black;
      break;
      
    case LED_FILE_TRANSFER:
      // Cyan breathing - file transfer
      if (ledDirection) {
        ledBrightness += 3;
        if (ledBrightness >= 200) {
          ledBrightness = 200;
          ledDirection = false;
        }
      } else {
        ledBrightness -= 3;
        if (ledBrightness <= 50) {
          ledBrightness = 50;
          ledDirection = true;
        }
      }
      leds[0] = CRGB(0, ledBrightness, ledBrightness); // Cyan
      break;
      
    case LED_BLE_CONNECTED:
      // White slow pulse - BLE connected
      leds[0] = ((now / 1500) % 2) ? CRGB::Blue : CRGB::Black;
      break;
  }
  
  FastLED.show();
}

// File Transfer Functions
void listSDFiles() {
  if (!sdCardAvailable) {
    sendFileResponse("ERROR:NO_SD_CARD");
    return;
  }
  
  String fileList = "FILES:";
  File root = SD_MMC.open("/");
  if (!root) {
    sendFileResponse("ERROR:CANT_OPEN_ROOT");
    return;
  }
  
  File file = root.openNextFile();
  while (file) {
    if (!file.isDirectory()) {
      String filename = file.name();
      if (filename.endsWith(".bin") || filename.endsWith(".log")) {
        fileList += filename + ":" + String(file.size()) + ";";
      }
    }
    file = root.openNextFile();
  }
  root.close();
  
  sendFileResponse(fileList);
  Serial.println("📁 File list sent: " + fileList);
}

void sendFileResponse(String response) {
  if (fileTransferChar) {
    // Split large responses into chunks
    int maxChunkSize = 500; // BLE MTU considerations
    for (int i = 0; i < response.length(); i += maxChunkSize) {
      String chunk = response.substring(i, min(i + maxChunkSize, (int)response.length()));
      fileTransferChar->setValue(chunk.c_str());
      fileTransferChar->notify();
      delay(50); // Small delay between chunks
    }
  }
}

void startFileTransfer(String filename) {
  if (!sdCardAvailable) {
    sendFileResponse("ERROR:NO_SD_CARD");
    return;
  }
  
  String fullPath = "/" + filename;
  if (!SD_MMC.exists(fullPath.c_str())) {
    sendFileResponse("ERROR:FILE_NOT_FOUND");
    return;
  }
  
  fileTransfer.transferFile = SD_MMC.open(fullPath.c_str(), FILE_READ);
  if (!fileTransfer.transferFile) {
    sendFileResponse("ERROR:CANT_OPEN_FILE");
    return;
  }
  
  fileTransfer.active = true;
  fileTransfer.filename = filename;
  fileTransfer.fileSize = fileTransfer.transferFile.size();
  fileTransfer.bytesSent = 0;
  fileTransfer.lastChunkTime = millis();
  
  setLEDStatus(LED_FILE_TRANSFER);
  
  // Send file info
  String response = "START:" + filename + ":" + String(fileTransfer.fileSize);
  sendFileResponse(response);
  
  Serial.printf("📤 Starting transfer: %s (%d bytes)\n", filename.c_str(), fileTransfer.fileSize);
}

void processFileTransfer() {
  if (!fileTransfer.active || !fileTransfer.transferFile) return;
  
  unsigned long now = millis();
  if (now - fileTransfer.lastChunkTime < 100) return; // Rate limiting
  
  const int chunkSize = 400; // Conservative chunk size for BLE
  uint8_t buffer[chunkSize];
  
  int bytesRead = fileTransfer.transferFile.read(buffer, chunkSize);
  if (bytesRead > 0) {
    // Convert to base64 for reliable BLE transmission
    String chunk = "CHUNK:";
    for (int i = 0; i < bytesRead; i++) {
      chunk += String(buffer[i], HEX);
      if (chunk.length() > 400) break; // Prevent overrun
    }
    
    sendFileResponse(chunk);
    fileTransfer.bytesSent += bytesRead;
    fileTransfer.lastChunkTime = now;
    
    // Progress indicator
    if (fileTransfer.bytesSent % 1000 == 0) {
      float progress = (float)fileTransfer.bytesSent / fileTransfer.fileSize * 100.0f;
      Serial.printf("📤 Transfer progress: %.1f%% (%d/%d bytes)\n", 
        progress, fileTransfer.bytesSent, fileTransfer.fileSize);
    }
  } else {
    // Transfer complete
    fileTransfer.transferFile.close();
    fileTransfer.active = false;
    
    sendFileResponse("COMPLETE:" + String(fileTransfer.bytesSent));
    Serial.printf("✅ Transfer complete: %s (%d bytes)\n", 
      fileTransfer.filename.c_str(), fileTransfer.bytesSent);
    
    // Return to appropriate LED status
    if (loggingActive) {
      setLEDStatus(LED_LOGGING);
    } else if (myGNSS.getFixType() >= 3) {
      setLEDStatus(LED_GPS_GOOD);
    } else {
      setLEDStatus(LED_GPS_SEARCHING);
    }
  }
}

void deleteFile(String filename) {
  if (!sdCardAvailable) {
    sendFileResponse("ERROR:NO_SD_CARD");
    return;
  }
  
  String fullPath = "/" + filename;
  if (SD_MMC.remove(fullPath.c_str())) {
    sendFileResponse("DELETED:" + filename);
    Serial.println("🗑️ Deleted: " + filename);
  } else {
    sendFileResponse("ERROR:DELETE_FAILED");
    Serial.println("❌ Failed to delete: " + filename);
  }
}

// CRC16 calculation
uint16_t crc16(const uint8_t* data, size_t length) {
  uint16_t crc = 0x0000;
  for (size_t i = 0; i < length; i++) {
    crc ^= (uint16_t)data[i] << 8;
    for (uint8_t j = 0; j < 8; j++) {
      if (crc & 0x8000)
        crc = (crc << 1) ^ 0x1021;
      else
        crc <<= 1;
    }
  }
  return crc;
}

// Initialize SD Card with enhanced error handling
bool initSDCard() {
  pinMode(SD_DETECT, INPUT_PULLDOWN);
  delay(100);
  
  if (digitalRead(SD_DETECT) == LOW) {
    Serial.println("❌ No SD card detected");
    setLEDStatus(LED_ERROR);
    return false;
  }
  
  Serial.println("📱 SD card detected, initializing...");
  
  SD_MMC.end();
  delay(100);
  
  if (SD_MMC.setPins(pin_sdioCLK, pin_sdioCMD, pin_sdioD0, pin_sdioD1, pin_sdioD2, pin_sdioD3) == false) {
    Serial.println("❌ SDIO pin assignment failed!");
    setLEDStatus(LED_ERROR);
    return false;
  }
  
  if (SD_MMC.begin() == false) {
    Serial.println("❌ SD_MMC Mount Failed");
    setLEDStatus(LED_ERROR);
    return false;
  }
  
  uint8_t cardType = SD_MMC.cardType();
  if (cardType == CARD_NONE) {
    Serial.println("❌ No SD card detected after mount");
    SD_MMC.end();
    setLEDStatus(LED_ERROR);
    return false;
  }
  
  // Test write capability
  File testFile = SD_MMC.open("/test_write.tmp", FILE_WRITE);
  if (testFile) {
    testFile.println("GPS Logger Test - " + String(millis()));
    testFile.close();
    SD_MMC.remove("/test_write.tmp");
    Serial.println("✅ SD card ready");
    return true;
  } else {
    Serial.println("❌ SD card write test failed");
    SD_MMC.end();
    setLEDStatus(LED_ERROR);
    return false;
  }
}

// Enhanced GNSS configuration
bool configureGNSS() {
  Serial.println("🛰️ Configuring GNSS...");
  setLEDStatus(LED_GPS_SEARCHING);
  
  // Disable NMEA output
  myGNSS.setUART1Output(COM_TYPE_UBX);
  myGNSS.setUART2Output(COM_TYPE_UBX);
  myGNSS.setI2COutput(COM_TYPE_UBX);
  myGNSS.setUSBOutput(COM_TYPE_UBX);
  
  // Disable specific NMEA messages
  myGNSS.disableNMEAMessage(UBX_NMEA_GLL, COM_PORT_UART1);
  myGNSS.disableNMEAMessage(UBX_NMEA_GSA, COM_PORT_UART1);
  myGNSS.disableNMEAMessage(UBX_NMEA_GSV, COM_PORT_UART1);
  myGNSS.disableNMEAMessage(UBX_NMEA_RMC, COM_PORT_UART1);
  myGNSS.disableNMEAMessage(UBX_NMEA_VTG, COM_PORT_UART1);
  myGNSS.disableNMEAMessage(UBX_NMEA_GGA, COM_PORT_UART1);
  
  // Set navigation frequency
  myGNSS.setNavigationFrequency(25);
  myGNSS.setAutoPVT(true);
  myGNSS.setAutoNAVSAT(true);
  
  // Set dynamic model
  if (myGNSS.setDynamicModel(DYN_MODEL_AUTOMOTIVE)) {
    Serial.println("✅ Dynamic model: AUTOMOTIVE");
  } else {
    Serial.println("❌ Failed to set dynamic model");
  }
  
  // Enable GNSS constellations
  myGNSS.enableGNSS(true, SFE_UBLOX_GNSS_ID_GPS);
  myGNSS.enableGNSS(true, SFE_UBLOX_GNSS_ID_GALILEO);
  myGNSS.enableGNSS(true, SFE_UBLOX_GNSS_ID_BEIDOU);
  myGNSS.enableGNSS(true, SFE_UBLOX_GNSS_ID_GLONASS);
  
  Serial.println("✅ GNSS configuration complete");
  return true;
}

// Create log file with GPS timestamp
bool createLogFile() {
  if (!sdCardAvailable) return false;
  
  sprintf(currentLogFilename, "/gps_%04d%02d%02d_%02d%02d%02d.bin",
    myGNSS.getYear(), myGNSS.getMonth(), myGNSS.getDay(),
    myGNSS.getHour(), myGNSS.getMinute(), myGNSS.getSecond());
  
  logFile = SD_MMC.open(currentLogFilename, FILE_WRITE);
  if (!logFile) {
    Serial.println("❌ Failed to create log file");
    setLEDStatus(LED_ERROR);
    return false;
  }
  
  Serial.printf("📄 Created: %s\n", currentLogFilename);
  
  // Write file header
  const char* header = "GPS_LOG_V1.0\n";
  logFile.write((uint8_t*)header, strlen(header));
  logFile.flush();
  
  return true;
}

// Enhanced BLE Configuration Callbacks
class ConfigCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    if (value.length() == 0) return;
    
    Serial.printf("📝 Config: %s\n", value.c_str());
    
    if (value == "START_LOG") {
      if (sdCardAvailable && myGNSS.getFixType() >= 2) {
        loggingActive = true;
        createLogFile();
        setLEDStatus(LED_LOGGING);
        Serial.println("🔴 Logging started via BLE");
      }
    } else if (value == "STOP_LOG") {
      loggingActive = false;
      if (logFile) {
        logFile.close();
        Serial.println("⚪ Logging stopped via BLE");
      }
      if (myGNSS.getFixType() >= 3) {
        setLEDStatus(LED_GPS_GOOD);
      } else {
        setLEDStatus(LED_GPS_SEARCHING);
      }
    } else if (value == "LIST_FILES") {
      listSDFiles();
    } else if (value.startsWith("DOWNLOAD:")) {
      String filename = value.substring(9);
      startFileTransfer(filename);
    } else if (value.startsWith("DELETE:")) {
      String filename = value.substring(7);
      deleteFile(filename);
    } else if (value == "LED_TEST") {
      // LED test sequence
      setLEDStatus(LED_STARTUP);
      delay(1000);
      setLEDStatus(LED_ERROR);
      delay(1000);
      setLEDStatus(LED_GPS_GOOD);
      delay(1000);
      setLEDStatus(LED_LOGGING);
    }
  }
};

// File Transfer Characteristic Callbacks
class FileTransferCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    Serial.printf("📤 File command: %s\n", value.c_str());
    
    if (value == "LIST") {
      listSDFiles();
    } else if (value.startsWith("GET:")) {
      String filename = value.substring(4);
      startFileTransfer(filename);
    } else if (value.startsWith("DEL:")) {
      String filename = value.substring(4);
      deleteFile(filename);
    } else if (value == "STOP") {
      if (fileTransfer.active) {
        fileTransfer.transferFile.close();
        fileTransfer.active = false;
        sendFileResponse("STOPPED");
        Serial.println("📤 File transfer stopped");
      }
    }
  }
};

// BLE Server Callbacks
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    Serial.println("📱 BLE Client connected");
    setLEDStatus(LED_BLE_CONNECTED);
  }
  
  void onDisconnect(BLEServer* pServer) {
    Serial.println("📱 BLE Client disconnected");
    BLEDevice::startAdvertising();
    
    // Return to appropriate status
    if (loggingActive) {
      setLEDStatus(LED_LOGGING);
    } else if (myGNSS.getFixType() >= 3) {
      setLEDStatus(LED_GPS_GOOD);
    } else {
      setLEDStatus(LED_GPS_SEARCHING);
    }
  }
};

void setup() {
  Serial.begin(115200);
  delay(5000);
  Serial.println("🚀 ESP32 GPS Logger v2.1 Starting...");
  Serial.println("💡 Simplified: Single Button + Main Display");
  
  // Initialize LED first for visual feedback
  initLED();
  setLEDStatus(LED_STARTUP);
  
  // Initialize button
  pinMode(BUTTON_A_PIN, INPUT_PULLUP);
  
  // Initialize SH1106 OLED display
  u8g2.begin();
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tr);
  u8g2.drawStr(0, 15, "GPS Logger v2.1");
  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(0, 30, "Initializing...");
  u8g2.drawStr(0, 45, "Button A = Record");
  u8g2.sendBuffer();
  
  // Initialize I2C and hardware sensors
  Wire.begin();
  Serial.println("🔍 Scanning I2C bus...");
  for (uint8_t address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      Serial.print("I2C device found at address 0x");
      if (address < 16) Serial.print("0");
      Serial.println(address, HEX);
    }
  }
  Serial.println("🔍 I2C scan complete.");
  
  // Initialize MPU6050
  initMPU6050();
  
  if (lipo.begin()) {
    lipo.quickStart();
    Serial.println("🔋 Battery monitor ready");
  } else {
    Serial.println("❌ Battery monitor failed");
  }
  
  // Update display
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tr);
  u8g2.drawStr(0, 15, "GPS Logger v2.1");
  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(0, 30, "Init SD Card...");
  u8g2.sendBuffer();
  
  // Initialize SD Card
  sdCardAvailable = initSDCard();
  
  // Update display
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tr);
  u8g2.drawStr(0, 15, "GPS Logger v2.1");
  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(0, 30, "Init GNSS...");
  u8g2.sendBuffer();
  
  // Initialize GNSS
  Serial.println("🛰️ Starting GNSS...");


  GNSS_Serial.begin(921600, SERIAL_8N1, GNSS_RX, GNSS_TX);
  if (!myGNSS.begin(GNSS_Serial)) {
  GNSS_Serial.begin(38400, SERIAL_8N1, GNSS_RX, GNSS_TX);
  Serial.println("🛰️ Starting GNSS at 38400 baud...");
  }

  if (!myGNSS.begin(GNSS_Serial)) {
    Serial.println("❌ GNSS not detected!");
    setLEDStatus(LED_NO_GPS);
    u8g2.clearBuffer();
    u8g2.setFont(u8g2_font_6x10_tr);
    u8g2.drawStr(0, 15, "GPS Logger v2.1");
    u8g2.setFont(u8g2_font_5x7_tr);
    u8g2.drawStr(0, 30, "GNSS ERROR!");
    u8g2.drawStr(0, 40, "Check connections");
    u8g2.sendBuffer();
    while (1) {
      updateLED();
      delay(100);
    }
  }
  
  myGNSS.setSerialRate(921600);
  delay(100);
  GNSS_Serial.updateBaudRate(921600); 

  if (!configureGNSS()) {
    Serial.println("❌ GNSS configuration failed!");
    setLEDStatus(LED_ERROR);
    while (1) {
      updateLED();
      delay(100);
    }
  }
  
  // Update display
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tr);
  u8g2.drawStr(0, 15, "GPS Logger v2.1");
  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(0, 30, "Init WiFi...");
  u8g2.sendBuffer();
  
  // Initialize WiFi
  Serial.println("📡 Connecting to WiFi...");
  WiFi.begin(ssid, password);
  unsigned long wifiStart = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - wifiStart < 15000) {
    delay(500);
    Serial.print(".");
    updateLED();
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.println("✅ WiFi connected!");
    Serial.print("📍 IP address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println();
    Serial.println("❌ WiFi connection failed");
  }
  
  // Update display
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tr);
  u8g2.drawStr(0, 15, "GPS Logger v2.1");
  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(0, 30, "Init BLE...");
  u8g2.sendBuffer();
  
  // Initialize BLE
  Serial.println("🔵 Initializing BLE...");
  BLEDevice::init("ESP32_GPS_Logger");
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  // Create BLE Service
  BLEService* pService = pServer->createService(telemetryServiceUUID);
  
  // Telemetry characteristic (notify)
  telemetryChar = pService->createCharacteristic(
    telemetryCharUUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  telemetryDescriptor = new BLE2902();
  telemetryChar->addDescriptor(telemetryDescriptor);
  
  // Configuration characteristic (write)
  configChar = pService->createCharacteristic(
    configCharUUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  configChar->setCallbacks(new ConfigCallbacks());
  
  // File transfer characteristic (read/write/notify)
  fileTransferChar = pService->createCharacteristic(
    fileTransferCharUUID,
    BLECharacteristic::PROPERTY_READ | 
    BLECharacteristic::PROPERTY_WRITE | 
    BLECharacteristic::PROPERTY_NOTIFY
  );
  fileTransferChar->setCallbacks(new FileTransferCallbacks());
  
  pService->start();
  
  // Start advertising
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(telemetryServiceUUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  pAdvertising->start();
  
  Serial.println("✅ BLE advertising started");
  
  // Final startup display
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_6x10_tr);
  u8g2.drawStr(0, 15, "GPS Logger v2.2");
  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(0, 30, "System Ready!");
  u8g2.drawStr(0, 40, "Press A to Record");
  if (mpuAvailable) {
    u8g2.drawStr(0, 50, "IMU: Active");
  } else {
    u8g2.drawStr(0, 50, "IMU: Not found");
  }
  u8g2.sendBuffer();
  
  delay(2000); // Show ready message
  
  Serial.println("🎯 System ready!");
  Serial.println("🎮 Button A: Start/Stop Recording");
  if (mpuAvailable) {
    Serial.println("🔄 MPU6050: Motion detection active");
  }
  
  setLEDStatus(LED_GPS_SEARCHING);
  perfStats.lastResetTime = millis();
  displayNeedsUpdate = true;
}

void loop() {
  static unsigned long lastPacketTime = 0;
  static unsigned long lastDebugTime = 0;
  static unsigned long lastWiFiCheck = 0;
  static unsigned long lastSDCheck = 0;
  static unsigned long lastBatteryCheck = 0;
  
  // Update LED continuously
  updateLED();
  
  // Process button input - HIGH PRIORITY
  processButtons();
  
  // Read IMU data - HIGH PRIORITY
  if (mpuAvailable) {
    readMPU6050();
  }
  
  // Update main display - HIGH PRIORITY  
  updateDisplay();
  
  // Process file transfers
  processFileTransfer();
  
  // Check battery level periodically
  if (millis() - lastBatteryCheck > 30000) {
    lastBatteryCheck = millis();
    float batteryVoltage = lipo.getVoltage();
    float batteryPercent = lipo.getSOC();
    
    if (batteryPercent < 15 && currentLEDStatus != LED_LOW_BATTERY && currentLEDStatus != LED_ERROR) {
      setLEDStatus(LED_LOW_BATTERY);
    }
    displayNeedsUpdate = true; // Update display when battery changes
  }
  
  // Check WiFi connection periodically  
  if (millis() - lastWiFiCheck > 30000) {
    lastWiFiCheck = millis();
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("📡 WiFi disconnected, attempting reconnect...");
      WiFi.reconnect();
      displayNeedsUpdate = true;
    }
  }
  
  // Check for SD card insertion/removal periodically
  if (millis() - lastSDCheck > 5000) {
    lastSDCheck = millis();
    bool cardPresent = digitalRead(SD_DETECT) == HIGH;
    if (cardPresent && !sdCardAvailable) {
      Serial.println("📱 SD card inserted, initializing...");
      sdCardAvailable = initSDCard();
      if (sdCardAvailable) {
        Serial.println("✅ SD card ready for logging");
      }
      displayNeedsUpdate = true;
    } else if (!cardPresent && sdCardAvailable) {
      Serial.println("📱 SD card removed");
      sdCardAvailable = false;
      if (logFile) {
        logFile.close();
        loggingActive = false;
        Serial.println("⚪ Logging stopped due to SD card removal");
      }
      SD_MMC.end();
      setLEDStatus(LED_ERROR);
      displayNeedsUpdate = true;
    }
  }
  
  // Process GPS data
  if (myGNSS.getPVT()) {
    unsigned long now = millis();
    unsigned long delta = now - lastPacketTime;
    
    // Update performance stats
    perfStats.totalPackets++;
    if (lastPacketTime > 0) {
      if (delta < perfStats.minDelta) perfStats.minDelta = delta;
      if (delta > perfStats.maxDelta) perfStats.maxDelta = delta;
      perfStats.avgDelta = (perfStats.avgDelta + delta) / 2;
    }
    lastPacketTime = now;
    
    // Update LED status based on GPS fix
    uint8_t fixType = myGNSS.getFixType();
    if (!loggingActive && !fileTransfer.active && currentLEDStatus != LED_LOW_BATTERY) {
      if (fixType >= 3) {
        setLEDStatus(LED_GPS_GOOD);
      } else if (fixType >= 1) {
        setLEDStatus(LED_GPS_SEARCHING);
      } else {
        setLEDStatus(LED_NO_GPS);
      }
    }
    
    // Create GPS packet
    GPSPacket packet;
    packet.timestamp = myGNSS.getUnixEpoch();
    packet.latitude = myGNSS.getLatitude();
    packet.longitude = myGNSS.getLongitude();
    packet.altitude = myGNSS.getAltitude();
    packet.speed = myGNSS.getGroundSpeed();
    packet.heading = myGNSS.getHeading();
    packet.fixType = fixType;
    packet.satellites = myGNSS.getSIV();
    
    // Battery data
    float battV = lipo.getVoltage();
    float soc = lipo.getSOC();
    packet.battery_mv = (uint16_t)(battV * 1000.0f);
    packet.battery_pct = (uint8_t)soc;
    
    // IMU data (if available)
    if (mpuAvailable) {
      packet.accel_x = (int16_t)(imuData.accelX * 1000);  // Convert g to mg
      packet.accel_y = (int16_t)(imuData.accelY * 1000);
      packet.accel_z = (int16_t)(imuData.accelZ * 1000);
      packet.gyro_x = (int16_t)(imuData.gyroX * 100);     // Convert deg/s to deg/s*100
      packet.gyro_y = (int16_t)(imuData.gyroY * 100);
    } else {
      packet.accel_x = 0;
      packet.accel_y = 0;
      packet.accel_z = 0;
      packet.gyro_x = 0;
      packet.gyro_y = 0;
    }
    
    packet.reserved1 = 0x00;
    
    // Calculate CRC on the payload (first 36 bytes - excluding the CRC field itself)
    packet.crc = crc16((uint8_t*)&packet, sizeof(GPSPacket) - 2);
    
    // Send via UDP if WiFi connected
    if (WiFi.status() == WL_CONNECTED) {
      udp.beginPacket(remoteIP, remotePort);
      udp.write((uint8_t*)&packet, sizeof(GPSPacket));
      udp.endPacket();
    }
    
    // Send via BLE if connected
    if (telemetryChar && telemetryDescriptor->getNotifications()) {
      telemetryChar->setValue((uint8_t*)&packet, sizeof(GPSPacket));
      telemetryChar->notify();
    }
    
    // Log to SD card if logging active
    if (loggingActive && logFile && sdCardAvailable) {
      size_t written = logFile.write((uint8_t*)&packet, sizeof(GPSPacket));
      if (written != sizeof(GPSPacket)) {
        Serial.println("❌ SD write error");
        perfStats.droppedPackets++;
        setLEDStatus(LED_ERROR);
      } else {
        logFile.flush();
      }
    }
    
    // Update display when GPS status changes significantly
    static uint8_t lastFixType = 0;
    static uint8_t lastSatellites = 0;
    static float lastSpeed = 0;
    float currentSpeed = myGNSS.getGroundSpeed() * 0.0036f;
    
    if (fixType != lastFixType || 
        abs((int)myGNSS.getSIV() - (int)lastSatellites) > 1 ||
        abs(currentSpeed - lastSpeed) > 1.0f) {
      displayNeedsUpdate = true;
      lastFixType = fixType;
      lastSatellites = myGNSS.getSIV();
      lastSpeed = currentSpeed;
    }
    
    // Debug output every 5 seconds
    if (now - lastDebugTime >= 5000) {
      lastDebugTime = now;
      
      Serial.printf("📊 GPS: %02d/%02d/%04d %02d:%02d:%02d UTC | ",
        myGNSS.getDay(), myGNSS.getMonth(), myGNSS.getYear(),
        myGNSS.getHour(), myGNSS.getMinute(), myGNSS.getSecond());
      
      Serial.printf("Fix: %d | Sats: %d | ", packet.fixType, packet.satellites);
      Serial.printf("Speed: %.1f km/h | ", currentSpeed);
      Serial.printf("Batt: %.1fV (%d%%)\n", battV, packet.battery_pct);
      
      Serial.printf("⚡ Performance: Δ=%lums (min:%lu, max:%lu, avg:%lu) | ",
        delta, perfStats.minDelta, perfStats.maxDelta, perfStats.avgDelta);
      Serial.printf("Packets: %lu | Dropped: %lu\n", 
        perfStats.totalPackets, perfStats.droppedPackets);
      
      // Reset min/max every debug cycle
      perfStats.minDelta = 9999;
      perfStats.maxDelta = 0;
      
      Serial.printf("🔗 WiFi: %s | BLE: %s | SD: %s | Log: %s\n",
        WiFi.status() == WL_CONNECTED ? "✅" : "❌",
        telemetryDescriptor->getNotifications() ? "✅" : "❌",
        sdCardAvailable ? "✅" : "❌",
        loggingActive ? "✅" : "❌");
      
      Serial.printf("🎮 Button A: %s\n", 
                    digitalRead(BUTTON_A_PIN) == LOW ? "PRESSED" : "RELEASED");
      
      // Memory usage
      Serial.printf("💾 Free RAM: %d bytes\n", ESP.getFreeHeap());
    }
  }
  
  // Small delay to prevent watchdog issues but keep responsive
  delay(5);
}