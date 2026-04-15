package com.Android.stremini_ai

import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import java.util.concurrent.TimeUnit

private val TRUSTED_BACKEND_HOSTS = setOf(
    "ai-keyboard-backend.vishwajeetadkine705.workers.dev",
    "agentic-github-debugger.vishwajeetadkine705.workers.dev",
)

class TrustedHostInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val url = request.url
        require(url.isHttps) { "Blocked non-HTTPS request to ${url.host}" }
        require(TRUSTED_BACKEND_HOSTS.contains(url.host)) {
            "Blocked request to untrusted host: ${url.host}"
        }
        return chain.proceed(request)
    }
}

fun secureHttpClient(
    connectTimeoutSeconds: Long,
    readTimeoutSeconds: Long,
): OkHttpClient = OkHttpClient.Builder()
    .addInterceptor(TrustedHostInterceptor())
    .connectTimeout(connectTimeoutSeconds, TimeUnit.SECONDS)
    .readTimeout(readTimeoutSeconds, TimeUnit.SECONDS)
    .build()

