package com.dailybloom.app

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    // TEMPORARY DIAGNOSTICS: exposes this install's package id and signing-cert
    // fingerprint so they can be compared with the Firebase Android OAuth
    // client on-device, without adb. Remove once sign-in works.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dailybloom.app/diagnostics",
        ).setMethodCallHandler { call, result ->
            if (call.method != "signingInfo") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                result.success(signingInfo())
            } catch (e: Exception) {
                result.error("signing_info_failed", e.message, null)
            }
        }
    }

    private fun signingInfo(): Map<String, String> {
        val pkg = packageName
        @Suppress("DEPRECATION")
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES)
        } else {
            packageManager.getPackageInfo(pkg, PackageManager.GET_SIGNATURES)
        }
        @Suppress("DEPRECATION")
        val certs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        val cert = certs?.firstOrNull() ?: throw IllegalStateException("no signer")

        fun digest(algorithm: String): String {
            val bytes = MessageDigest.getInstance(algorithm).digest(cert.toByteArray())
            return bytes.joinToString(":") { String.format("%02X", it) }
        }

        return mapOf(
            "packageName" to pkg,
            "sha1" to digest("SHA-1"),
            "sha256" to digest("SHA-256"),
            "versionName" to (info.versionName ?: "?"),
        )
    }
}
