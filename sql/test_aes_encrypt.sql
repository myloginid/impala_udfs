-- Impala UDF tests for aes_encrypt
-- Adapted from Apache Hive test:
-- https://github.com/apache/hive/blob/770e70c98360ac0b029db46675e0dc5cd0e9040c/ql/src/test/queries/clientpositive/udf_aes_encrypt.q
--
-- Prereq: run sql/create_function.sql to register functions (adjust DB/path if needed).

-- Optional function introspection
DESCRIBE FUNCTION default.aes_encrypt;
-- DESCRIBE FUNCTION EXTENDED default.aes_encrypt;

EXPLAIN SELECT default.aes_encrypt('ABC', '1234567890123456');

-- Deterministic outputs (HEX shown for portability across engines)
-- Expected HEX (computed via OpenSSL AES/ECB/PKCS7):
--  - AES-128: aes_encrypt('ABC','1234567890123456') -> CBA4ACFB309839BA426E07D67F23564F
--  - AES-128: aes_encrypt('',   '1234567890123456') -> 050187A0CDE5A9872CBAB091AB73E553
SELECT
  HEX(default.aes_encrypt('ABC', '1234567890123456'))   AS hex_abc,
  HEX(default.aes_encrypt('',    '1234567890123456'))   AS hex_empty;

-- NULL propagation and invalid key lengths (should return NULL)
SELECT
  default.aes_encrypt(CAST(NULL AS STRING), '1234567890123456')  AS null_input_is_null,
  default.aes_encrypt('ABC', CAST(NULL AS STRING))               AS null_key_is_null,
  default.aes_encrypt('ABC', '12345678901234567')                AS key_len_17_is_null,
  default.aes_encrypt('ABC', '123456789012345')                  AS key_len_15_is_null,
  default.aes_encrypt('ABC', '')                                 AS empty_key_is_null;

-- If your Impala has TO_BASE64, these should match the Hive test strings:
--  y6Ss+zCYObpCbgfWfyNWTw== (for 'ABC')
--  BQGHoM3lqYcsurCRq3PlUw== (for '')
-- SELECT
--   TO_BASE64(default.aes_encrypt('ABC','1234567890123456')) AS b64_abc,
--   TO_BASE64(default.aes_encrypt('',   '1234567890123456')) AS b64_empty;

