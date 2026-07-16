# PeekDock Hardware Context

目标板卡为 **Waveshare ESP32-S3-Touch-LCD-1.47**。没有实物时，浏览器 simulator 是完整的 Demo 替代方案，不阻塞 Runtime 与产品验收。

## 已确认规格

- MCU：ESP32-S3R8，双核 240MHz
- Flash / PSRAM：16MB / 8MB
- 屏幕：1.47 英寸 IPS，172×320，RGB565，JD9853，4-wire SPI
- 触摸：AXS5106L，I2C，单点触摸/手势
- USB：USB-Serial/JTAG
- 无线：2.4GHz Wi-Fi、BLE 5
- 默认串口：`/dev/cu.usbmodem1301`（可用 `PEEKDOCK_SERIAL_PORT` 覆盖）

## GPIO

| 功能 | GPIO |
| --- | ---: |
| LCD_SCLK | 38 |
| LCD_MOSI | 39 |
| LCD_CS | 21 |
| LCD_DC | 45 |
| LCD_RST | 40 |
| LCD_BL | 48 |
| TP_SDA | 17 |
| TP_SCL | 18 |
| TP_INT | 16 |
| SD_CS | 14 |

## 固件基线

- ESP-IDF 5.2+
- LVGL 9.x
- 项目入口：[src/app/app_main.cpp](src/app/app_main.cpp)
- UI：[src/ui/screens/peekdock_screen.cpp](src/ui/screens/peekdock_screen.cpp)
- 协议：[src/protocol/task_protocol.cpp](src/protocol/task_protocol.cpp)
- 板级驱动：[components/esp_bsp](components/esp_bsp)、[components/esp_lcd_jd9853](components/esp_lcd_jd9853)、[components/esp_lcd_touch_axs5106](components/esp_lcd_touch_axs5106)

不要自行编造 JD9853 或 AXS5106L 初始化序列；仓库内 Waveshare 来源驱动是 bring-up 真相源。

## 构建与烧录

```bash
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/cu.usbmodem1301 flash monitor
```

`partitions.csv` 为 factory app 分配 6MB；工程启用 16MB Flash 和 octal PSRAM。MVP 固件包含 Codex、Claude、Jimeng、Browser 四页角色素材。

## 无实物验收

```bash
npm install
npm start
```

打开 <http://127.0.0.1:4173>。Bridge 找不到串口时显示 `MOCK SERIAL`，Web simulator 仍消费相同 `task_snapshot` / `task_update` 状态。

若换用其他板卡，必须先确认 panel/touch driver、GPIO、分辨率、旋转、字节序和 PSRAM，再修改 UI。
