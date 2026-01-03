package org.fossify.messages.receivers

// Add this code to your existing SmsReceiver.kt

import android.content.Context
import android.util.Log
import org.fossify.messages.helpers.Config
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Webhook notification client
 * 
 * Add this function to your SMS/MMS receiver
 * Call it whenever an SMS or MMS is received
 */
private fun notifyWebhook(
    context: Context,
    phoneNumber: String,
    message: String,
    attachments: List<String> = emptyList()
) {
    // Load webhook configuration
    val config = Config.newInstance(context)
    val webhookUrl = config.webhookUrl
    val webhookToken = config.webhookToken
    
    // Skip if webhook not configured
    if (webhookUrl.isEmpty()) {
        Log.d("SmsReceiver", "Webhook not configured, skipping")
        return
    }
    
    // Send webhook asynchronously (don't block SMS receive)
    Thread {
        try {
            val url = URL(webhookUrl)
            val connection = url.openConnection() as HttpURLConnection
            
            // Configure request
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $webhookToken")
            connection.doOutput = true
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            
            // Build JSON payload
            val json = JSONObject()
            json.put("phoneNumber", phoneNumber)
            json.put("message", message)
            
            if (attachments.isNotEmpty()) {
                json.put("attachments", JSONArray(attachments))
                json.put("type", "mms")
            } else {
                json.put("type", "sms")
            }
            
            json.put("receivedAt", System.currentTimeMillis())
            
            // Send request
            connection.outputStream.use { os ->
                os.write(json.toString().toByteArray())
            }
            
            // Check response
            val responseCode = connection.responseCode
            if (responseCode == 200) {
                Log.d("SmsReceiver", "Webhook sent successfully")
            } else {
                Log.w("SmsReceiver", "Webhook returned $responseCode")
            }
            
            connection.disconnect()
        } catch (e: Exception) {
            Log.e("SmsReceiver", "Webhook error", e)
            // Don't throw - webhook failure shouldn't break SMS receive
        }
    }.start()
}

/**
 * Example usage in your SMS receiver:
 */
override fun onReceive(context: Context, intent: Intent) {
    // ... existing SMS receive code ...
    
    val phoneNumber = extractPhoneNumber(intent)
    val messageBody = extractMessageBody(intent)
    
    // Notify webhook
    notifyWebhook(context, phoneNumber, messageBody)
    
    // ... rest of SMS handling ...
}

/**
 * Example usage for MMS:
 */
private fun handleMms(context: Context, phoneNumber: String, message: String, attachments: List<String>) {
    // ... existing MMS handling ...
    
    // Notify webhook with attachments
    notifyWebhook(context, phoneNumber, message, attachments)
}

/**
 * Add to Config.kt:
 */
var webhookUrl: String
    get() = prefs.getString(WEBHOOK_URL, "").toString()
    set(webhookUrl) = prefs.edit().putString(WEBHOOK_URL, webhookUrl).apply()

var webhookToken: String
    get() = prefs.getString(WEBHOOK_TOKEN, "").toString()
    set(webhookToken) = prefs.edit().putString(WEBHOOK_TOKEN, webhookToken).apply()

var apiPort: Int
    get() = prefs.getInt(API_PORT, 8080)
    set(port) = prefs.edit().putInt(API_PORT, port).apply()

var apiToken: String
    get() = prefs.getString(API_TOKEN, "").toString()
    set(token) = prefs.edit().putString(API_TOKEN, token).apply()

companion object {
    const val WEBHOOK_URL = "webhook_url"
    const val WEBHOOK_TOKEN = "webhook_token"
    const val API_PORT = "api_port"
    const val API_TOKEN = "api_token"
}
