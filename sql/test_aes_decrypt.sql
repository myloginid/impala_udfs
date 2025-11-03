-- Impala UDF tests for aes_decrypt
-- Adapted from Apache Hive test:
-- https://github.com/apache/hive/blob/770e70c98360ac0b029db46675e0dc5cd0e9040c/ql/src/test/queries/clientpositive/udf_aes_decrypt.q
--
-- Prereq: run sql/create_function.sql to register functions (adjust DB/path if needed).

-- Optional function introspection
DESCRIBE FUNCTION default.aes_decrypt;
-- DESCRIBE FUNCTION EXTENDED default.aes_decrypt;

-- Example plan
EXPLAIN SELECT default.aes_decrypt(UNHEX('CBA4ACFB309839BA426E07D67F23564F'), '1234567890123456');

-- Decrypt known ciphertexts (HEX inputs from test_aes_encrypt.sql expectations)
--  HEX 'CBA4ACFB309839BA426E07D67F23564F'  -> 'ABC'
--  HEX '050187A0CDE5A9872CBAB091AB73E553' -> '' (empty string)
SELECT
  default.aes_decrypt(UNHEX('CBA4ACFB309839BA426E07D67F23564F'), '1234567890123456') = 'ABC' AS dec_abc_ok,
  default.aes_decrypt(UNHEX('050187A0CDE5A9872CBAB091AB73E553'), '1234567890123456') = ''    AS dec_empty_ok;

-- NULL propagation and invalid key lengths (should return NULL)
SELECT
  default.aes_decrypt(CAST(NULL AS STRING), '1234567890123456')                        AS null_input_is_null,
  default.aes_decrypt(UNHEX('CBA4ACFB309839BA426E07D67F23564F'), CAST(NULL AS STRING)) AS null_key_is_null,
  default.aes_decrypt(UNHEX('CBA4ACFB309839BA426E07D67F23564F'), '12345678901234567')  AS key_len_17_is_null,
  default.aes_decrypt(UNHEX('CBA4ACFB309839BA426E07D67F23564F'), '123456789012345')    AS key_len_15_is_null,
  default.aes_decrypt(UNHEX('CBA4ACFB309839BA426E07D67F23564F'), '')                   AS empty_key_is_null;

-- If your Impala has FROM_BASE64, these mirror the Hive tests:
--  FROM_BASE64('y6Ss+zCYObpCbgfWfyNWTw==') -> 'ABC'
--  FROM_BASE64('BQGHoM3lqYcsurCRq3PlUw==') -> ''
-- SELECT
--   default.aes_decrypt(FROM_BASE64('y6Ss+zCYObpCbgfWfyNWTw=='), '1234567890123456') = 'ABC' AS b64_abc_ok,
--   default.aes_decrypt(FROM_BASE64('BQGHoM3lqYcsurCRq3PlUw=='), '1234567890123456') = ''    AS b64_empty_ok;

