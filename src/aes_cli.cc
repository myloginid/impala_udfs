// Lightweight CLI to exercise AES-ECB/PKCS7 logic used by the UDFs.
// Not dependent on Impala headers; builds anywhere with OpenSSL.

#include <openssl/evp.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>
#include <string.h>
#include <stdio.h>
#include <string>
#include <vector>

static const EVP_CIPHER* cipher_for_keylen(int key_len) {
  switch (key_len) {
    case 16: return EVP_aes_128_ecb();
    case 24: return EVP_aes_192_ecb();
    case 32: return EVP_aes_256_ecb();
    default: return nullptr;
  }
}

static bool aes_encrypt_ecb_pkcs7(const unsigned char* in, int in_len,
                                  const unsigned char* key, int key_len,
                                  std::vector<unsigned char>& out) {
  const EVP_CIPHER* c = cipher_for_keylen(key_len);
  if (!c) return false;

  EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
  if (!ctx) return false;
  int ok = 1, outl1 = 0, outl2 = 0;
  out.assign(in_len + EVP_CIPHER_block_size(c), 0);
  ok &= EVP_EncryptInit_ex(ctx, c, nullptr, key, nullptr);
  ok &= EVP_CIPHER_CTX_set_padding(ctx, 1);
  ok &= EVP_EncryptUpdate(ctx, out.data(), &outl1, in, in_len);
  ok &= EVP_EncryptFinal_ex(ctx, out.data() + outl1, &outl2);
  EVP_CIPHER_CTX_free(ctx);
  if (!ok) return false;
  out.resize(outl1 + outl2);
  return true;
}

static bool aes_decrypt_ecb_pkcs7(const unsigned char* in, int in_len,
                                  const unsigned char* key, int key_len,
                                  std::vector<unsigned char>& out) {
  const EVP_CIPHER* c = cipher_for_keylen(key_len);
  if (!c) return false;
  EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
  if (!ctx) return false;
  int ok = 1, outl1 = 0, outl2 = 0;
  out.assign(in_len, 0);
  ok &= EVP_DecryptInit_ex(ctx, c, nullptr, key, nullptr);
  ok &= EVP_CIPHER_CTX_set_padding(ctx, 1);
  ok &= EVP_DecryptUpdate(ctx, out.data(), &outl1, in, in_len);
  ok &= EVP_DecryptFinal_ex(ctx, out.data() + outl1, &outl2);
  EVP_CIPHER_CTX_free(ctx);
  if (!ok) return false;
  out.resize(outl1 + outl2);
  return true;
}

static std::string to_hex(const std::vector<unsigned char>& v) {
  static const char* kHex = "0123456789abcdef";
  std::string s;
  s.reserve(v.size() * 2);
  for (auto b : v) {
    s.push_back(kHex[(b >> 4) & 0xF]);
    s.push_back(kHex[b & 0xF]);
  }
  return s;
}

static std::string to_base64(const std::vector<unsigned char>& v) {
  BIO* b64 = BIO_new(BIO_f_base64());
  BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
  BIO* mem = BIO_new(BIO_s_mem());
  b64 = BIO_push(b64, mem);
  BIO_write(b64, v.data(), (int)v.size());
  BIO_flush(b64);
  BUF_MEM* bptr = nullptr;
  BIO_get_mem_ptr(b64, &bptr);
  std::string out(bptr->data, bptr->length);
  BIO_free_all(b64);
  return out;
}

int main(int argc, char** argv) {
  if (argc < 4) {
    fprintf(stderr, "Usage: %s enc|dec <key> <input>\n", argv[0]);
    return 2;
  }
  std::string mode = argv[1];
  std::string key = argv[2];
  std::string input = argv[3];
  int key_len = (int)key.size();
  if (!(key_len == 16 || key_len == 24 || key_len == 32)) {
    fprintf(stderr, "key length must be 16/24/32 bytes\n");
    return 3;
  }

  std::vector<unsigned char> out;
  bool ok = false;
  if (mode == "enc") {
    ok = aes_encrypt_ecb_pkcs7((const unsigned char*)input.data(), (int)input.size(),
                               (const unsigned char*)key.data(), key_len, out);
  } else if (mode == "dec") {
    ok = aes_decrypt_ecb_pkcs7((const unsigned char*)input.data(), (int)input.size(),
                               (const unsigned char*)key.data(), key_len, out);
  } else {
    fprintf(stderr, "unknown mode: %s\n", mode.c_str());
    return 4;
  }

  if (!ok) {
    fprintf(stderr, "crypto failed\n");
    return 5;
  }

  printf("hex:%s\n", to_hex(out).c_str());
  printf("b64:%s\n", to_base64(out).c_str());
  return 0;
}
