package com.keskai.easydict

import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.util.Log
import android.view.View
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val windowChannel = "com.keskai.easydict/window"
    private val TAG = "EasyDictWindow"

    // OnLayoutChangeListener 只注册一次，直接绑定在 DecorView 上，
    // 不依赖 ViewTreeObserver（后者在 Surface 重建后会 die/失效）。
    private var layoutListenerAttached = false

    // -----------------------------------------------------------------------
    // 配置 MethodChannel：
    //   1. onMultiWindowModeChanged → Flutter 侧覆盖 MediaQuery padding
    //   2. setWindowBackground → 接收 Flutter 主题色，设置 window background，
    //      使小窗顶栏 / 底栏区域的颜色与 App 内容背景精确匹配，实现视觉沉浸
    // -----------------------------------------------------------------------
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, windowChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWindowBackground" -> {
                        val colorInt = call.argument<Int>("color")
                        if (colorInt != null) {
                            window.setBackgroundDrawable(ColorDrawable(colorInt))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        applyEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "onResume: isInMultiWindowMode=$isInMultiWindowMode")
        extendContentUnderBars()
        syncWindowStateToFlutter()
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        Log.d(TAG, "onMultiWindowModeChanged: isInMultiWindowMode=$isInMultiWindowMode")
        applyEdgeToEdge()
        extendContentUnderBars()
        syncWindowStateToFlutter()
        ViewCompat.requestApplyInsets(window.decorView)
        window.decorView.findViewWithTag<View>("flutter_view")?.let {
            Log.d(TAG, "onMultiWindowModeChanged: 对 FlutterView 触发 requestApplyInsets")
            ViewCompat.requestApplyInsets(it)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        Log.d(TAG, "onWindowFocusChanged: hasFocus=$hasFocus, isInMultiWindowMode=$isInMultiWindowMode")
        if (hasFocus) {
            applyEdgeToEdge()
            extendContentUnderBars()
            syncWindowStateToFlutter()
            ViewCompat.requestApplyInsets(window.decorView)
            window.decorView.findViewWithTag<View>("flutter_view")?.let {
                Log.d(TAG, "onWindowFocusChanged: 对 FlutterView 触发 requestApplyInsets")
                ViewCompat.requestApplyInsets(it)
            }
        }
    }

    private fun applyEdgeToEdge() {
        Log.d(TAG, "applyEdgeToEdge called, isInMultiWindowMode=$isInMultiWindowMode")
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // DecorView 层拦截：让修正后的 insets 沿 View 树向下分发
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { view, insets ->
            val corrected = buildCorrectedInsets(insets, "DecorView")
            ViewCompat.dispatchApplyWindowInsets(view, corrected)
            corrected
        }

        // -----------------------------------------------------------------------
        // 关键：直接在 FlutterView 上覆盖 listener
        //
        // Flutter 引擎通过 FlutterView 的 OnApplyWindowInsetsListener 读取 insets，
        // 在 DecorView 层修改后调用 dispatchApplyWindowInsets 会传播下去，
        // 但 Flutter 引擎在某些情况下（onCreate 后、requestApplyInsets 触发时）
        // 会跳过分发链直接用 getRootWindowInsets()，绕开 DecorView 的拦截。
        //
        // 在 FlutterView（tag="flutter_view"）上直接设置 listener，
        // 是拦截 Flutter 引擎最终看到的 insets 的唯一可靠方式。
        // -----------------------------------------------------------------------
        window.decorView.post {
            val flutterView = window.decorView.findViewWithTag<View>("flutter_view")
            Log.d(TAG, "FlutterView 查找结果: ${if (flutterView != null) "已找到，注册拦截器" else "未找到"}")
            if (flutterView != null) {
                ViewCompat.setOnApplyWindowInsetsListener(flutterView) { fView, insets ->
                    val corrected = buildCorrectedInsets(insets, "FlutterView")
                    ViewCompat.onApplyWindowInsets(fView, corrected)
                    corrected
                }
                // 让 Flutter 引擎立即以修正后的值重新计算 viewport
                ViewCompat.requestApplyInsets(flutterView)
            }
        }
    }

    /**
     * 核心修复：持续抹除系统在 freeform 模式下设置的 DecorView freeformPadding。
     *
     * 日志明确显示系统通过 DecorView 内部的 updateFreeformWindow() 设置：
     *   I/DecorView: freeformPadding, set to new padding Rect(0,0-0,0) -> Rect(0,134-0,48)
     *
     * 之前用 ViewTreeObserver.OnGlobalLayoutListener 的方案失效，原因：
     * Surface 重建（BufferQueueProducer disconnect/connect）时 ViewTreeObserver
     * 会变成 isAlive=false，已注册的 listener 不再回调，日志里看不到任何
     * "clearFreeformPadding" 输出即是证明。
     *
     * 换用 View.addOnLayoutChangeListener：
     * - 直接绑定在 View 对象上，不受 VTO 生命周期影响
     * - 每次 View 的 layout 坐标/尺寸变化后都会回调
     * - 一次注册，永久有效
     */
    private fun extendContentUnderBars() {
        // 立刻尝试清除已存在的 freeformPadding（进入小窗时同步生效）
        clearFreeformPadding("extendContentUnderBars 主动清除")

        if (layoutListenerAttached) {
            Log.d(TAG, "extendContentUnderBars: OnLayoutChangeListener 已注册，跳过")
            return
        }
        layoutListenerAttached = true

        window.decorView.addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
            // DecorView 任何 layout 变化后检测，若 freeformPadding 非零立即清除
            if (view.paddingTop != 0 || view.paddingBottom != 0) {
                clearFreeformPadding("OnLayoutChangeListener top=${view.paddingTop} bottom=${view.paddingBottom}")
            }
        }
        Log.d(TAG, "extendContentUnderBars: OnLayoutChangeListener 已注册")
    }

    /**
     * 清除 DecorView 的 freeformPadding 并触发 Flutter 重新计算 viewport。
     */
    private fun clearFreeformPadding(reason: String) {
        val decorView = window.decorView
        val topBefore    = decorView.paddingTop
        val bottomBefore = decorView.paddingBottom
        if (topBefore == 0 && bottomBefore == 0) return
        Log.d(TAG, "clearFreeformPadding [$reason]: top=$topBefore bottom=$bottomBefore → 0")
        decorView.setPadding(0, 0, 0, 0)
        // 重新分发 insets，让 Flutter 引擎以修正后的 viewport 重绘
        ViewCompat.requestApplyInsets(decorView)
        decorView.findViewWithTag<View>("flutter_view")?.let {
            ViewCompat.requestApplyInsets(it)
        }
    }

    /**
     * 小窗模式下将 caption/status/navigation insets 全部归零，
     * 使 Flutter 引擎不为这些区域添加 viewport padding，
     * FlutterSurface 延伸至 window 顶部实现 edge-to-edge。
     */
    private fun buildCorrectedInsets(insets: WindowInsetsCompat, from: String): WindowInsetsCompat {
        val captionTop = insets.getInsets(WindowInsetsCompat.Type.captionBar()).top
        val statusTop  = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top
        val navBottom  = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
        return if (isInMultiWindowMode) {
            Log.d(TAG, "$from insets(原): captionBar.top=$captionTop status.top=$statusTop nav.bottom=$navBottom → 小窗模式归零")
            WindowInsetsCompat.Builder(insets)
                .setInsets(WindowInsetsCompat.Type.captionBar(),     Insets.NONE)
                .setInsets(WindowInsetsCompat.Type.statusBars(),     Insets.NONE)
                .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.NONE)
                .build()
        } else {
            Log.d(TAG, "$from insets(原): captionBar.top=$captionTop status.top=$statusTop nav.bottom=$navBottom → 全屏模式不修改")
            insets
        }
    }

    private fun syncWindowStateToFlutter() {
        val inMultiWindow = isInMultiWindowMode
        val rootInsets = ViewCompat.getRootWindowInsets(window.decorView)
        val captionPx = rootInsets?.getInsets(WindowInsetsCompat.Type.captionBar())?.top ?: 0
        val statusPx  = rootInsets?.getInsets(WindowInsetsCompat.Type.statusBars())?.top ?: 0
        val topBarPx  = if (inMultiWindow) maxOf(captionPx, statusPx) else 0
        val navPx     = rootInsets?.getInsets(WindowInsetsCompat.Type.navigationBars())?.bottom ?: 0
        val gesturePx = rootInsets?.getInsets(WindowInsetsCompat.Type.systemGestures())?.bottom ?: 0
        val bottomBarPx = if (inMultiWindow) maxOf(navPx, gesturePx) else 0
        notifyFlutter(
            isMultiWindow = inMultiWindow,
            captionBarHeight = topBarPx,
            bottomBarHeight = bottomBarPx
        )
    }

    private fun notifyFlutter(isMultiWindow: Boolean, captionBarHeight: Int, bottomBarHeight: Int) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, windowChannel).invokeMethod(
                "onMultiWindowModeChanged",
                mapOf(
                    "isMultiWindow" to isMultiWindow,
                    "captionBarHeight" to captionBarHeight,
                    "bottomBarHeight" to bottomBarHeight
                )
            )
        }
    }
}
