package de.mcbuchi.trailbuddy

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Der einzige native Code im Projekt (Muster PilzBuddy): ein
 * MethodChannel, der die geladene Update-APK dem System-Installer
 * übergibt. Beendigungsgründe und Netz-Messung aus PilzBuddy kommen mit
 * ihren Features, nicht auf Vorrat — jede Zeile hier hat kein Test-Netz.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        /** Update der GitHub-APK: fertige Datei an den System-Installer geben.
         *  Der Name steht in Dart in `lib/data/apk_installer.dart`; ein Test
         *  hält beide zusammen. */
        const val INSTALL_CHANNEL = "de.mcbuchi.trailbuddy/apk_install"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstall())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("no_path", "Pfad fehlt", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Ab Android 8 eine Freigabe je App; darunter immer erlaubt (minSdk 24). */
    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** Systemeinstellung für genau diese App öffnen, nicht die globale Liste. */
    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /**
     * Über einen FileProvider statt `file://` (ab Android 7 verboten); der
     * Installer läuft in einem fremden Prozess und braucht die Leseerlaubnis.
     * Installiert wird NICHT still: Das System fragt. Deshalb reicht
     * REQUEST_INSTALL_PACKAGES.
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "Datei nicht gefunden: $path", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
            result.success(true)
        } catch (e: Exception) {
            // Dart fällt daraufhin auf den Browser-Download zurück.
            result.error("install_failed", e.message, null)
        }
    }
}
