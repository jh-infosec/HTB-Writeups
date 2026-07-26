import base64
from itertools import cycle

enc_password = base64.b64decode(
        "0Nv32PTwgYjzg9/8j5TbmvPd3e7WhtWWyuPsyO76/Y+U193E"
)

key = b"armando"

result = ""

for encrypted_byte, key_byte in zip(enc_password, cycle(key)):
        result += chr(encrypted_byte ^ key_byte ^ 223)

print(result)

