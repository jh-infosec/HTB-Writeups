# Security Tools

Small utilities I've written while working through cybersecurity labs, Hack The Box machines, and security research.

These tools automate repetitive tasks, reduce manual errors, and turn techniques I learn into reusable scripts.

All tools are intended for authorized lab and educational environments.


## Tools


### rogue-jndi-helper.sh

Bash helper created while working through the Hack The Box Unified machine.

Automates parts of the Rogue-JNDI setup, including payload generation, Base64 validation, and listener configuration.

More tools will be added as I build them.

### userinfo-decrypt.py

Python implementation of the password decryption routine discovered while reverse engineering `UserInfo.exe` on the Hack The Box Support machine.

The original routine was identified by decompiling the .NET application with ILSpy. The script reproduces the application's XOR-based transformation to recover the LDAP credential from the encrypted value and embedded key.

Created to understand and reproduce the application's credential handling rather than manually calculating the transformation.
