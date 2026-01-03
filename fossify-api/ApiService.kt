package org.fossify.messages.api

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import org.fossify.commons.extensions.showToast
import org.fossify.messages.R
import org.fossify.messages.helpers.Config

/**
 * Background service to run the API server
 * Starts when app launches (if enabled in settings)
 * Runs continuously while phone is on
 */
class ApiService : Service() {
    
    private var apiServer: ApiServer? = null
    
    companion object {
        private const val TAG = "ApiService"
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "ApiService created")
        
        // Load configuration from shared preferences
        val config = Config.newInstance(applicationContext)
        val port = config.apiPort
        val token = config.apiToken
        
        if (port > 0 && token.isNotEmpty()) {
            try {
                // Start HTTP server
                apiServer = ApiServer(applicationContext, port, token)
                apiServer?.start()
                
                Log.i(TAG, "API server started on port $port")
                showToast(R.string.api_server_started)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start API server", e)
                showToast(R.string.api_server_error)
            }
        } else {
            Log.w(TAG, "API server not configured properly")
        }
    }
    
    override fun onDestroy() {
        Log.d(TAG, "ApiService destroyed")
        
        // Stop HTTP server
        try {
            apiServer?.stop()
            Log.i(TAG, "API server stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping API server", e)
        }
        
        super.onDestroy()
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        // This service doesn't support binding
        return null
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Restart service if killed by system
        return START_STICKY
    }
}
