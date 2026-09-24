package com.todart.todart_txt

import android.accounts.Account
import android.accounts.AccountManager
import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "todart_txt/saf_sync"
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestSync" -> {
                        val synced = requestSavedSync()
                        result.success(mapOf("synced" to synced))
                    }
                    "pickAccount" -> {
                        pendingPick = result
                        try {
                            // No type filter: any sync account. Picking grants
                            // this app account visibility (persists across
                            // restarts).
                            val intent = AccountManager.newChooseAccountIntent(
                                null, null, null, null, null, null, null
                            )
                            startActivityForResult(intent, REQ_PICK_ACCOUNT)
                        } catch (e: Exception) {
                            Log.e(TAG, "pickAccount: failed to launch picker", e)
                            pendingPick = null
                            result.success(mapOf("picked" to false))
                        }
                    }
                    "clearAccount" -> {
                        prefs().edit().clear().apply()
                        Log.d(TAG, "clearAccount: saved sync account cleared")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_ACCOUNT) return
        val reply = pendingPick
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            Log.d(TAG, "pickAccount: cancelled")
            reply?.success(mapOf("picked" to false))
            return
        }
        val name = data.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
        val type = data.getStringExtra(AccountManager.KEY_ACCOUNT_TYPE)
        if (name.isNullOrEmpty() || type.isNullOrEmpty()) {
            Log.d(TAG, "pickAccount: no account returned")
            reply?.success(mapOf("picked" to false))
            return
        }
        prefs().edit().putString(KEY_NAME, name).putString(KEY_TYPE, type).apply()
        Log.d(TAG, "pickAccount: saved $name ($type)")
        requestSavedSync()
        reply?.success(mapOf("picked" to true, "name" to name, "type" to type))
    }

    /** Syncs the persisted account (granted via picker). False when none. */
    private fun requestSavedSync(): Boolean {
        try {
            val prefs = prefs()
            val name = prefs.getString(KEY_NAME, null)
            val type = prefs.getString(KEY_TYPE, null)
            if (name.isNullOrEmpty() || type.isNullOrEmpty()) {
                Log.d(TAG, "requestSync: no saved sync account, picker needed")
                return false
            }
            val am = AccountManager.get(this)
            val account = am.getAccountsByType(type).firstOrNull { it.name == name }
            if (account == null) {
                Log.d(TAG, "requestSync: saved account $name ($type) not visible, picker needed")
                return false
            }
            syncAccount(account)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "requestSync: failed", e)
            return false
        }
    }

    private fun syncAccount(account: Account) {
        // Sync authority registered for this account type (looked up from
        // the system's registered sync adapters).
        val syncAdapters = ContentResolver.getSyncAdapterTypes()
        val authority = syncAdapters.firstOrNull { it.accountType == account.type }?.authority
        if (authority == null) {
            Log.d(TAG, "requestSync: no sync authority for ${account.name} (${account.type}), skipping")
            return
        }
        val extras = Bundle().apply {
            putBoolean(ContentResolver.SYNC_EXTRAS_MANUAL, true)
            putBoolean(ContentResolver.SYNC_EXTRAS_EXPEDITED, true)
        }
        Log.d(TAG, "requestSync: requesting expedited manual sync for ${account.name} ($authority)")
        ContentResolver.requestSync(account, authority, extras)
    }

    private fun prefs() = getSharedPreferences(PREFS, MODE_PRIVATE)

    companion object {
        private const val TAG = "SafSync"
        private const val PREFS = "todart_saf_sync"
        private const val KEY_NAME = "account_name"
        private const val KEY_TYPE = "account_type"
        private const val REQ_PICK_ACCOUNT = 7319
    }
}
