# Console UI Master（Flutter 薄客户端）

手机端入口，对齐电脑上的「AI 工具中心」。

## 架构

- **电脑 Node**（`picture_prompt_produce`）：密钥、模型、Comfy、情绪对话全在服务端 `.env`
- **本 App**：只保存局域网地址（如 `http://192.168.0.128:3000`），调 REST / SSE，**不存 API Key**

## 使用

1. 电脑启动 Node：`npm start`（默认端口 3000）
2. 手机与电脑同一 Wi‑Fi
3. App 右上角设置填：`http://你的电脑IPv4:3000` → 测试并保存
4. 首页点「角色扮演」或「ComfyUI 图片生成」

## 开发

```bash
flutter pub get
flutter run
```
