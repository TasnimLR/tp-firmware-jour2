# CVEs détectées — Netgear R7000

| CVE | CVSS | Description | Preuve |
|-----|------|-------------|--------|
| CVE-2016-6277 | 9.8 | RCE sans auth via `/cgi-bin/;CMD` | `input_vali_getstrtosys` dans httpd |
| CVE-2017-5521 | 9.8 | Auth bypass + password leak via `unauth.cgi` | `passwordrecovered.cgi` dans httpd |
| CVE-2009-4964 | 10.0 | Backdoor telnet UDP `telnetenabled` | Binaire présent + strings MD5/socket |
| CVE-2016-10176 | 7.5 | Password disclosure `passwordrecovered.cgi` | Référence dans httpd strings |
| CVE-2013-2678 | 7.8 | OpenSSL 1.0.2h — multiples failles | `OpenSSL 1.0.2h 3 May 2016` dans libcrypto |
| Générique | - | Pas de Stack Canary / ASLR / RELRO | `GNU_STACK RW` sans PIE |
| Générique | - | Kernel 2.6.36 (2010) | `Linux kernel version 2.6.36` dans binwalk |
