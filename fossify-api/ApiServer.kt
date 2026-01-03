package org.fossify.messages.api

import android.content.Context
import android.telephony.SmsManager
import com.google.gson.Gson
import fi.iki.elonen.NanoHTTPD
import org.fossify.messages.helpers.MessagingUtils
import java.io.File
import java.util.*

/**
 * HTTP API Server for Fossify Messages
 * 
 * Provides REST API endpoints for:
 * - Sending SMS
 * - Sending MMS
 * - Health check
 */
class ApiServer(
    private val context: Context,
    port: Int,
    private val authToken: String
) : NanoHTTPD(port) {
    
    private val gson = Gson()
    
    override fun serve(session: IHTTPSession): Response {
        // Authenticate all requests
        val authHeader = session.headers["authorization"]
        if (authHeader != "Bearer $authToken") {
            return newFixedLengthResponse(
                Response.Status.UNAUTHORIZED,
                "application/json",
                """{"error":"Unauthorized"}"""
            )
        }
        
        // Route requests
        return when {
            session.uri == "/send_sms" && session.method == Method.POST -> 
                handleSendSms(session)
            session.uri == "/send_mms" && session.method == Method.POST -> 
                handleSendMms(session)
            session.uri == "/health" && session.method == Method.GET -> 
                handleHealth()
            else -> newFixedLengthResponse(
                Response.Status.NOT_FOUND,
                "application/json",
                """{"error":"Not found"}"""
            )
        }
    }
    
    private fun handleSendSms(session: IHTTPSession): Response {
        try {
            val body = parseBody(session)
            val phoneNumber = body["phoneNumber"] as? String
            val message = body["message"] as? String
            
            if (phoneNumber == null || message == null) {
                return newFixedLengthResponse(
                    Response.Status.BAD_REQUEST,
                    "application/json",
                    """{"error":"Missing phoneNumber or message"}"""
                )
            }
            
            // Send SMS using Android API
            val smsManager = SmsManager.getDefault()
            
            // Handle long messages (split if needed)
            if (message.length > 160) {
                val parts = smsManager.divideMessage(message)
                smsManager.sendMultipartTextMessage(
                    phoneNumber,
                    null,
                    parts,
                    null,
                    null
                )
            } else {
                smsManager.sendTextMessage(
                    phoneNumber,
                    null,
                    message,
                    null,
                    null
                )
            }
            
            return newFixedLengthResponse(
                Response.Status.OK,
                "application/json",
                """{"status":"sent","id":"${System.currentTimeMillis()}"}"""
            )
        } catch (e: Exception) {
            return newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR,
                "application/json",
                """{"error":"${e.message}"}"""
            )
        }
    }
    
    private fun handleSendMms(session: IHTTPSession): Response {
        try {
            val body = parseBody(session)
            val phoneNumber = body["phoneNumber"] as? String
            val message = body["message"] as? String ?: ""
            val attachments = body["attachments"] as? List<String> ?: emptyList()
            
            if (phoneNumber == null) {
                return newFixedLengthResponse(
                    Response.Status.BAD_REQUEST,
                    "application/json",
                    """{"error":"Missing phoneNumber"}"""
                )
            }
            
            // Decode base64 attachments and save to temp files
            val tempFiles = attachments.mapIndexed { index, base64Data ->
                val bytes = Base64.getDecoder().decode(base64Data)
                val file = File(context.cacheDir, "mms_temp_$index.jpg")
                file.writeBytes(bytes)
                file
            }
            
            // Send MMS using Fossify's messaging utilities
            // This uses native Android MMS APIs
            MessagingUtils.sendMMS(
                context,
                phoneNumber,
                message,
                tempFiles.map { android.net.Uri.fromFile(it) }
            )
            
            // Cleanup temp files
            tempFiles.forEach { it.delete() }
            
            return newFixedLengthResponse(
                Response.Status.OK,
                "application/json",
                """{"status":"sent","id":"${System.currentTimeMillis()}"}"""
            )
        } catch (e: Exception) {
            return newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR,
                "application/json",
                """{"error":"${e.message}"}"""
            )
        }
    }
    
    private fun handleHealth(): Response {
        return newFixedLengthResponse(
            Response.Status.OK,
            "application/json",
            """{"status":"ok","server":"fossify-api"}"""
        )
    }
    
    private fun parseBody(session: IHTTPSession): Map<String, Any> {
        val body = mutableMapOf<String, String>()
        session.parseBody(body)
        val json = body["postData"] ?: "{}"
        @Suppress("UNCHECKED_CAST")
        return gson.fromJson(json, Map::class.java) as Map<String, Any>
    }
}
