package com.frelsical.nativeapp.settings

import android.content.Context
import android.util.Base64
import android.util.Log
import androidx.core.content.edit
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Encrypts the CalDAV password with a key held in the Android Keystore so it is
 * never written to disk in plain text.
 */
class SecureStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun readPassword(): String {
        val payload = prefs.getString(KEY_PASSWORD, null) ?: return ""
        return try {
            val bytes = Base64.decode(payload, Base64.NO_WRAP)
            val buffer = ByteBuffer.wrap(bytes)
            val ivLength = buffer.int
            require(ivLength in 1..64)
            val iv = ByteArray(ivLength).also(buffer::get)
            val encrypted = ByteArray(buffer.remaining()).also(buffer::get)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(TAG_BITS, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (exception: Exception) {
            Log.w(TAG, "Unable to decrypt stored password; clearing it", exception)
            prefs.edit { remove(KEY_PASSWORD) }
            ""
        }
    }

    fun writePassword(password: String) {
        if (password.isEmpty()) {
            prefs.edit { remove(KEY_PASSWORD) }
            return
        }
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            val iv = cipher.iv
            val encrypted = cipher.doFinal(password.toByteArray(Charsets.UTF_8))
            val payload = ByteBuffer.allocate(Int.SIZE_BYTES + iv.size + encrypted.size)
                .putInt(iv.size)
                .put(iv)
                .put(encrypted)
                .array()
            prefs.edit {
                putString(KEY_PASSWORD, Base64.encodeToString(payload, Base64.NO_WRAP))
            }
        } catch (exception: Exception) {
            Log.e(TAG, "Unable to encrypt CalDAV password", exception)
        }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }

        val generator = KeyGenerator.getInstance(
            "AES",
            KEYSTORE_PROVIDER,
        )
        generator.init(
            android.security.keystore.KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or
                    android.security.keystore.KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val TAG = "SecureStore"
        const val PREFS_NAME = "frelsi_secure"
        const val KEY_PASSWORD = "caldav_password"
        const val KEY_ALIAS = "frelsi_caldav_credentials"
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val TAG_BITS = 128
    }
}
