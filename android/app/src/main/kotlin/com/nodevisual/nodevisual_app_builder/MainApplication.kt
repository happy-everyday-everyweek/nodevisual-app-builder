package com.nodevisual.nodevisual_app_builder

import android.content.Context
import android.util.Log
import io.flutter.app.FlutterApplication
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 自定义 Application，用于在 Flutter 框架初始化之前捕获 Java 层未处理异常。
 *
 * Dart 层的 try/catch 无法覆盖插件注册、FlutterEngine 初始化等原生阶段发生的崩溃。
 * 通过 [Thread.setDefaultUncaughtExceptionHandler] 把这些异常写入外部可访问的日志文件，
 * 方便无 ADB 环境时排查启动闪退。
 */
class MainApplication : FlutterApplication() {

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        installGlobalExceptionHandler()
    }

    private fun installGlobalExceptionHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                writeJavaCrashLog(throwable)
            } catch (e: Exception) {
                Log.e("MainApplication", "写入崩溃日志失败", e)
            }
            // 继续交给系统默认处理器，保持正常崩溃行为（生成 tombstone 等）。
            defaultHandler?.uncaughtException(thread, throwable)
        }
    }

    private fun writeJavaCrashLog(throwable: Throwable) {
        val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date())
        val sw = StringWriter()
        throwable.printStackTrace(PrintWriter(sw))

        val log = buildString {
            appendLine("=== NodeVisual Java Crash Log ===")
            appendLine("Time: $time")
            appendLine("Thread: ${Thread.currentThread().name}")
            appendLine("Exception: ${throwable.javaClass.name}")
            appendLine("Message: ${throwable.message}")
            appendLine("Stack:")
            appendLine(sw.toString())
            appendLine("=================================")
        }

        // 写入应用专属外部目录，无需运行时权限（Android 10+ 豁免）。
        val externalDir = File("/sdcard/Android/data/com.nodevisual.nodevisual_app_builder/files")
        if (!externalDir.exists()) {
            externalDir.mkdirs()
        }
        File(externalDir, "native_crash.log").writeText(log)

        // 同时写入内部 files 目录作为备份。
        File(filesDir, "native_crash.log").writeText(log)
    }
}
