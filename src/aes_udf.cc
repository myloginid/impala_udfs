// Impala AES Encrypt/Decrypt UDFs
// Cipher: AES-ECB with PKCS#7 padding (Hive-compatible)

#include <openssl/evp.h>
#include <openssl/crypto.h>
#include <openssl/opensslv.h>
#include <string.h>

#include <impala_udf/udf.h>

using namespace impala_udf;

namespace {

#if OPENSSL_VERSION_NUMBER < 0x10100000L
// Backport helpers for OpenSSL 1.0.2 (no *_new/_free APIs)
static inline EVP_CIPHER_CTX* EVP_CIPHER_CTX_new_compat() {
  EVP_CIPHER_CTX* ctx = (EVP_CIPHER_CTX*)OPENSSL_malloc(sizeof(EVP_CIPHER_CTX));
  if (ctx) {
    memset(ctx, 0, sizeof(EVP_CIPHER_CTX));
    EVP_CIPHER_CTX_init(ctx);
  }
  return ctx;
}
static inline void EVP_CIPHER_CTX_free_compat(EVP_CIPHER_CTX* ctx) {
  if (ctx) {
    EVP_CIPHER_CTX_cleanup(ctx);
    OPENSSL_free(ctx);
  }
}
#define EVP_CIPHER_CTX_new EVP_CIPHER_CTX_new_compat
#define EVP_CIPHER_CTX_free EVP_CIPHER_CTX_free_compat
#endif

static const EVP_CIPHER* CipherFromKeyBits(int key_bits) {
  switch (key_bits) {
    case 128: return EVP_aes_128_ecb();
    case 192: return EVP_aes_192_ecb();
    case 256: return EVP_aes_256_ecb();
    default: return nullptr;
  }
}

} // namespace

extern "C" StringVal aes_encrypt(FunctionContext* ctx, const StringVal& input, const StringVal& key) {
  if (input.is_null || key.is_null) return StringVal::null();

  // Hive compatibility:
  // - Accept only key lengths of 16/24/32 bytes. Otherwise return NULL.
  int key_len = key.len;
  if (!(key_len == 16 || key_len == 24 || key_len == 32)) {
    return StringVal::null();
  }

  unsigned char keybuf[32];
  memset(keybuf, 0, sizeof(keybuf));
  memcpy(keybuf, key.ptr, key_len);

  const EVP_CIPHER* cipher = CipherFromKeyBits(key_len * 8);
  if (cipher == nullptr) {
    return StringVal::null();
  }

  EVP_CIPHER_CTX* cctx = EVP_CIPHER_CTX_new();
  if (!cctx) {
    ctx->SetError("aes_encrypt: EVP_CIPHER_CTX_new failed");
    return StringVal::null();
  }

  StringVal out(ctx, input.len + EVP_CIPHER_block_size(cipher));
  if (out.ptr == nullptr) {
    EVP_CIPHER_CTX_free(cctx);
    return StringVal::null();
  }

  int outl1 = 0;
  int outl2 = 0;
  int ok = 1;

  ok &= EVP_EncryptInit_ex(cctx, cipher, nullptr, keybuf, nullptr);
  // Ensure PKCS#7 padding (enabled by default, set explicitly for clarity)
  ok &= EVP_CIPHER_CTX_set_padding(cctx, 1);
  if (!ok) {
    EVP_CIPHER_CTX_free(cctx);
    return StringVal::null();
  }

  ok &= EVP_EncryptUpdate(cctx,
                          reinterpret_cast<unsigned char*>(out.ptr), &outl1,
                          reinterpret_cast<const unsigned char*>(input.ptr), input.len);
  if (!ok) {
    EVP_CIPHER_CTX_free(cctx);
    return StringVal::null();
  }

  ok &= EVP_EncryptFinal_ex(cctx,
                            reinterpret_cast<unsigned char*>(out.ptr) + outl1,
                            &outl2);
  EVP_CIPHER_CTX_free(cctx);

  if (!ok) {
    return StringVal::null();
  }

  out.len = outl1 + outl2;
  return out;
}

extern "C" StringVal aes_decrypt(FunctionContext* ctx, const StringVal& input, const StringVal& key) {
  if (input.is_null || key.is_null) return StringVal::null();

  // Hive compatibility: key length must be 16/24/32 bytes
  int key_len = key.len;
  if (!(key_len == 16 || key_len == 24 || key_len == 32)) {
    return StringVal::null();
  }

  const EVP_CIPHER* cipher = CipherFromKeyBits(key_len * 8);
  if (cipher == nullptr) {
    return StringVal::null();
  }

  unsigned char keybuf[32];
  memset(keybuf, 0, sizeof(keybuf));
  memcpy(keybuf, key.ptr, key_len);

  // For decrypt, allocate at least input.len (padding reduced in final)
  StringVal out(ctx, input.len);
  if (out.ptr == nullptr) {
    return StringVal::null();
  }

  EVP_CIPHER_CTX* cctx = EVP_CIPHER_CTX_new();
  if (!cctx) {
    return StringVal::null();
  }

  int ok = 1;
  int outl1 = 0;
  int outl2 = 0;

  ok &= EVP_DecryptInit_ex(cctx, cipher, nullptr, keybuf, nullptr);
  ok &= EVP_CIPHER_CTX_set_padding(cctx, 1);
  if (!ok) {
    EVP_CIPHER_CTX_free(cctx);
    return StringVal::null();
  }

  ok &= EVP_DecryptUpdate(cctx,
                          reinterpret_cast<unsigned char*>(out.ptr), &outl1,
                          reinterpret_cast<const unsigned char*>(input.ptr), input.len);
  if (!ok) {
    EVP_CIPHER_CTX_free(cctx);
    return StringVal::null();
  }

  ok &= EVP_DecryptFinal_ex(cctx, reinterpret_cast<unsigned char*>(out.ptr) + outl1, &outl2);
  EVP_CIPHER_CTX_free(cctx);
  if (!ok) {
    return StringVal::null();
  }

  out.len = outl1 + outl2;
  return out;
}
