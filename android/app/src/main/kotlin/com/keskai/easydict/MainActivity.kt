package com.keskai.easydict

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 让 Flutter 自行处理所有系统窗口 insets，实现 edge-to-edge
        // 在 super.onCreate 之前调用，确保对所有 Android 版本生效（含小窗/多窗口模式）
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
}
