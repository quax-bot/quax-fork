package com.teskann.quax

import android.webkit.WebView
import androidx.webkit.UserAgentMetadata
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

/**
 * Gives WebViews the user agent metadata (`sec-ch-ua*`) of Chrome. Otherwise they list themselves as "Android WebView"
 * whatever their user agent says. Older WebViews keep their own.
 */
object WebViewUserAgentMetadata {
    fun set(engine: FlutterEngine, webViewIdentifier: Long, brands: List<Map<String, String>>, fullVersion: String) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA)) return
        // MainActivity has no plugin binding to pass to the newer overload
        @Suppress("DEPRECATION")
        val webView = WebViewFlutterAndroidExternalApi.getWebView(engine, webViewIdentifier) ?: return
        val metadata = UserAgentMetadata.Builder(WebSettingsCompat.getUserAgentMetadata(webView.settings))
            .setBrandVersionList(brands.map(::toBrandVersion))
            .setFullVersion(fullVersion)
            .build()
        WebSettingsCompat.setUserAgentMetadata(webView.settings, metadata)
    }

    fun copy(from: WebView, to: WebView) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA)) return
        WebSettingsCompat.setUserAgentMetadata(to.settings, WebSettingsCompat.getUserAgentMetadata(from.settings))
    }

    // Keys sent by login_webview.dart
    private fun toBrandVersion(brand: Map<String, String>): UserAgentMetadata.BrandVersion =
        UserAgentMetadata.BrandVersion.Builder()
            .setBrand(brand.getValue("name"))
            .setMajorVersion(brand.getValue("majorVersion"))
            .setFullVersion(brand.getValue("fullVersion"))
            .build()
}
