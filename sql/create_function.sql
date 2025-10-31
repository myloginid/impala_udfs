-- Adjust DB + HDFS path as needed
CREATE FUNCTION IF NOT EXISTS default.aes_encrypt(string, string)
RETURNS string
LOCATION '/user/udf/lib/libaes_udf.so'
SYMBOL='aes_encrypt';

CREATE FUNCTION IF NOT EXISTS default.aes_decrypt(string, string)
RETURNS string
LOCATION '/user/udf/lib/libaes_udf.so'
SYMBOL='aes_decrypt';

-- Example usage:
-- SELECT hex(default.aes_encrypt('hello','secretkey'));
-- SELECT CAST(default.aes_decrypt(default.aes_encrypt('hello','secretkey'), 'secretkey') AS STRING);
