# SHA1.pmod - Re-enable SHA1 certificate support
# Based on the UBI 9 DEFAULT:SHA1 subpolicy which was removed in RHEL 10.
# Required for Azure PostgreSQL connections using SHA1-signed certificates.

hash = SHA1+

sign = ECDSA-SHA1+ RSA-PSS-SHA1+ RSA-SHA1+
