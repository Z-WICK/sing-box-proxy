# TLS

> 作者: nekohasekai
> 原文链接: https://sing-box.sagernet.org/configuration/shared/tls/

---
# TLS

Changes in sing-box 1.14.0

[certificate\_provider](#certificate_provider)
[handshake\_timeout](#handshake_timeout)
[spoof](#spoof)
[spoof\_method](#spoof_method)
[acme](#acme-fields)

Changes in sing-box 1.13.0

[kernel\_tx](#kernel_tx)
[kernel\_rx](#kernel_rx)
[curve\_preferences](#curve_preferences)
[certificate\_public\_key\_sha256](#certificate_public_key_sha256)
[client\_certificate](#client_certificate)
[client\_certificate\_path](#client_certificate_path)
[client\_key](#client_key)
[client\_key\_path](#client_key_path)
[client\_authentication](#client_authentication)
[client\_certificate\_public\_key\_sha256](#client_certificate_public_key_sha256)
[ech.query\_server\_name](#query_server_name)

Changes in sing-box 1.12.0

[fragment](#fragment)
[fragment\_fallback\_delay](#fragment_fallback_delay)
[record\_fragment](#record_fragment)
[ech.pq\_signature\_schemes\_enabled](#pq_signature_schemes_enabled)
[ech.dynamic\_record\_sizing\_disabled](#dynamic_record_sizing_disabled)

Changes in sing-box 1.10.0

[utls](#utls)

### Inbound

`[](#__codelineno-0-1){ [](#__codelineno-0-2)  "enabled": true, [](#__codelineno-0-3)  "server_name": "", [](#__codelineno-0-4)  "alpn": [], [](#__codelineno-0-5)  "min_version": "", [](#__codelineno-0-6)  "max_version": "", [](#__codelineno-0-7)  "cipher_suites": [], [](#__codelineno-0-8)  "curve_preferences": [], [](#__codelineno-0-9)  "certificate": [], [](#__codelineno-0-10)  "certificate_path": "", [](#__codelineno-0-11)  "client_authentication": "", [](#__codelineno-0-12)  "client_certificate": [], [](#__codelineno-0-13)  "client_certificate_path": [], [](#__codelineno-0-14)  "client_certificate_public_key_sha256": [], [](#__codelineno-0-15)  "key": [], [](#__codelineno-0-16)  "key_path": "", [](#__codelineno-0-17)  "kernel_tx": false, [](#__codelineno-0-18)  "kernel_rx": false, [](#__codelineno-0-19)  "handshake_timeout": "", [](#__codelineno-0-20)  "certificate_provider": "", [](#__codelineno-0-21) [](#__codelineno-0-22)  // Deprecated [](#__codelineno-0-23) [](#__codelineno-0-24)  "acme": { [](#__codelineno-0-25)    "domain": [], [](#__codelineno-0-26)    "data_directory": "", [](#__codelineno-0-27)    "default_server_name": "", [](#__codelineno-0-28)    "email": "", [](#__codelineno-0-29)    "provider": "", [](#__codelineno-0-30)    "disable_http_challenge": false, [](#__codelineno-0-31)    "disable_tls_alpn_challenge": false, [](#__codelineno-0-32)    "alternative_http_port": 0, [](#__codelineno-0-33)    "alternative_tls_port": 0, [](#__codelineno-0-34)    "external_account": { [](#__codelineno-0-35)      "key_id": "", [](#__codelineno-0-36)      "mac_key": "" [](#__codelineno-0-37)    }, [](#__codelineno-0-38)    "dns01_challenge": {} [](#__codelineno-0-39)  }, [](#__codelineno-0-40)  "ech": { [](#__codelineno-0-41)    "enabled": false, [](#__codelineno-0-42)    "key": [], [](#__codelineno-0-43)    "key_path": "", [](#__codelineno-0-44) [](#__codelineno-0-45)    // Deprecated [](#__codelineno-0-46) [](#__codelineno-0-47)    "pq_signature_schemes_enabled": false, [](#__codelineno-0-48)    "dynamic_record_sizing_disabled": false [](#__codelineno-0-49)  }, [](#__codelineno-0-50)  "reality": { [](#__codelineno-0-51)    "enabled": false, [](#__codelineno-0-52)    "handshake": { [](#__codelineno-0-53)      "server": "google.com", [](#__codelineno-0-54)      "server_port": 443, [](#__codelineno-0-55) [](#__codelineno-0-56)      ... // Dial Fields [](#__codelineno-0-57)    }, [](#__codelineno-0-58)    "private_key": "UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc", [](#__codelineno-0-59)    "short_id": [ [](#__codelineno-0-60)      "0123456789abcdef" [](#__codelineno-0-61)    ], [](#__codelineno-0-62)    "max_time_difference": "1m" [](#__codelineno-0-63)  } [](#__codelineno-0-64)}`

### Outbound

`[](#__codelineno-1-1){ [](#__codelineno-1-2)  "enabled": true, [](#__codelineno-1-3)  "engine": "", [](#__codelineno-1-4)  "disable_sni": false, [](#__codelineno-1-5)  "server_name": "", [](#__codelineno-1-6)  "insecure": false, [](#__codelineno-1-7)  "alpn": [], [](#__codelineno-1-8)  "min_version": "", [](#__codelineno-1-9)  "max_version": "", [](#__codelineno-1-10)  "cipher_suites": [], [](#__codelineno-1-11)  "curve_preferences": [], [](#__codelineno-1-12)  "certificate": "", [](#__codelineno-1-13)  "certificate_path": "", [](#__codelineno-1-14)  "certificate_public_key_sha256": [], [](#__codelineno-1-15)  "client_certificate": [], [](#__codelineno-1-16)  "client_certificate_path": "", [](#__codelineno-1-17)  "client_key": [], [](#__codelineno-1-18)  "client_key_path": "", [](#__codelineno-1-19)  "fragment": false, [](#__codelineno-1-20)  "fragment_fallback_delay": "", [](#__codelineno-1-21)  "record_fragment": false, [](#__codelineno-1-22)  "spoof": "", [](#__codelineno-1-23)  "spoof_method": "", [](#__codelineno-1-24)  "kernel_tx": false, [](#__codelineno-1-25)  "kernel_rx": false, [](#__codelineno-1-26)  "handshake_timeout": "", [](#__codelineno-1-27)  "ech": { [](#__codelineno-1-28)    "enabled": false, [](#__codelineno-1-29)    "config": [], [](#__codelineno-1-30)    "config_path": "", [](#__codelineno-1-31)    "query_server_name": "", [](#__codelineno-1-32) [](#__codelineno-1-33)    // Deprecated [](#__codelineno-1-34)    "pq_signature_schemes_enabled": false, [](#__codelineno-1-35)    "dynamic_record_sizing_disabled": false [](#__codelineno-1-36)  }, [](#__codelineno-1-37)  "utls": { [](#__codelineno-1-38)    "enabled": false, [](#__codelineno-1-39)    "fingerprint": "" [](#__codelineno-1-40)  }, [](#__codelineno-1-41)  "reality": { [](#__codelineno-1-42)    "enabled": false, [](#__codelineno-1-43)    "public_key": "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0", [](#__codelineno-1-44)    "short_id": "0123456789abcdef" [](#__codelineno-1-45)  } [](#__codelineno-1-46)}`

TLS version values:

-   `1.0`
-   `1.1`
-   `1.2`
-   `1.3`

Cipher suite values:

-   `TLS_RSA_WITH_AES_128_CBC_SHA`
-   `TLS_RSA_WITH_AES_256_CBC_SHA`
-   `TLS_RSA_WITH_AES_128_GCM_SHA256`
-   `TLS_RSA_WITH_AES_256_GCM_SHA384`
-   `TLS_AES_128_GCM_SHA256`
-   `TLS_AES_256_GCM_SHA384`
-   `TLS_CHACHA20_POLY1305_SHA256`
-   `TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA`
-   `TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA`
-   `TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA`
-   `TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA`
-   `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256`
-   `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`
-   `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`
-   `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`
-   `TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256`
-   `TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256`

You can ignore the JSON Array \[\] tag when the content is only one item

### Fields

#### enabled

Enable TLS.

#### engine

Client only

TLS engine to use.

Values:

-   `go` (default)
-   `apple`

`apple` uses Network.framework, only available on Apple platforms and only supports **direct** TCP TLS client connections.

Experimental only: due to the high memory overhead of both CGO and Network.framework, do not use in hot paths on iOS and tvOS. If you want to circumvent TLS fingerprint-based proxy censorship, use [NaiveProxy](/configuration/outbound/naive/) instead.

Supported fields:

-   `server_name`
-   `insecure`
-   `alpn`
-   `min_version`
-   `max_version`
-   `certificate` / `certificate_path`
-   `certificate_public_key_sha256`
-   `handshake_timeout`

Unsupported fields:

-   `disable_sni`
-   `cipher_suites`
-   `curve_preferences`
-   `client_certificate` / `client_certificate_path` / `client_key` / `client_key_path`
-   `fragment` / `record_fragment`
-   `kernel_tx` / `kernel_rx`
-   `ech`
-   `utls`
-   `reality`

#### disable\_sni

Client only

Do not send server name in ClientHello.

#### server\_name

Used to verify the hostname on the returned certificates unless insecure is given.

It is also included in the client's handshake to support virtual hosting unless it is an IP address.

#### insecure

Client only

Accepts any server certificate.

#### alpn

List of supported application level protocols, in order of preference.

If both peers support ALPN, the selected protocol will be one from this list, and the connection will fail if there is no mutually supported protocol.

See [Application-Layer Protocol Negotiation](https://en.wikipedia.org/wiki/Application-Layer_Protocol_Negotiation).

#### min\_version

The minimum TLS version that is acceptable.

By default, TLS 1.2 is currently used as the minimum when acting as a client, and TLS 1.0 when acting as a server.

#### max\_version

The maximum TLS version that is acceptable.

By default, the maximum version is currently TLS 1.3.

#### cipher\_suites

List of enabled TLS 1.0–1.2 cipher suites. The order of the list is ignored. Note that TLS 1.3 cipher suites are not configurable.

If empty, a safe default list is used. The default cipher suites might change over time.

#### curve\_preferences

Since sing-box 1.13.0

Set of supported key exchange mechanisms. The order of the list is ignored, and key exchange mechanisms are chosen from this list using an internal preference order by Golang.

Available values, also the default list:

-   `P256`
-   `P384`
-   `P521`
-   `X25519`
-   `X25519MLKEM768`

#### certificate

Server certificates chain line array, in PEM format.

#### certificate\_path

Will be automatically reloaded if file modified.

The path to server certificate chain, in PEM format.

#### certificate\_public\_key\_sha256

Since sing-box 1.13.0

Client only

List of SHA-256 hashes of server certificate public keys, in base64 format.

To generate the SHA-256 hash for a certificate's public key, use the following commands:

`[](#__codelineno-2-1)# For a certificate file [](#__codelineno-2-2)openssl x509 -in certificate.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64 [](#__codelineno-2-3) [](#__codelineno-2-4)# For a certificate from a remote server [](#__codelineno-2-5)echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64`

#### client\_certificate

Since sing-box 1.13.0

Client only

Client certificate chain line array, in PEM format.

#### client\_certificate\_path

Since sing-box 1.13.0

Client only

The path to client certificate chain, in PEM format.

#### client\_key

Since sing-box 1.13.0

Client only

Client private key line array, in PEM format.

#### client\_key\_path

Since sing-box 1.13.0

Client only

The path to client private key, in PEM format.

#### key

Server only

The server private key line array, in PEM format.

#### key\_path

Server only

Will be automatically reloaded if file modified.

The path to the server private key, in PEM format.

#### client\_authentication

Since sing-box 1.13.0

Server only

The type of client authentication to use.

Available values:

-   `no` (default)
-   `request`
-   `require-any`
-   `verify-if-given`
-   `require-and-verify`

One of `client_certificate`, `client_certificate_path`, or `client_certificate_public_key_sha256` is required if this option is set to `verify-if-given`, or `require-and-verify`.

#### client\_certificate

Since sing-box 1.13.0

Server only

Client certificate chain line array, in PEM format.

#### client\_certificate\_path

Since sing-box 1.13.0

Server only

Will be automatically reloaded if file modified.

List of path to client certificate chain, in PEM format.

#### client\_certificate\_public\_key\_sha256

Since sing-box 1.13.0

Server only

List of SHA-256 hashes of client certificate public keys, in base64 format.

To generate the SHA-256 hash for a certificate's public key, use the following commands:

`[](#__codelineno-3-1)# For a certificate file [](#__codelineno-3-2)openssl x509 -in certificate.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64 [](#__codelineno-3-3) [](#__codelineno-3-4)# For a certificate from a remote server [](#__codelineno-3-5)echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64`

#### kernel\_tx

Since sing-box 1.13.0

Only supported on Linux 5.1+, use a newer kernel if possible.

Only TLS 1.3 is supported.

kTLS TX may only improve performance when `splice(2)` is available (both ends must be TCP or TLS without additional protocols after handshake); otherwise, it will definitely degrade performance.

Enable kernel TLS transmit support.

#### kernel\_rx

Since sing-box 1.13.0

Only supported on Linux 5.1+, use a newer kernel if possible.

Only TLS 1.3 is supported.

kTLS RX will definitely degrade performance even if `splice(2)` is in use, so enabling it is not recommended.

Enable kernel TLS receive support.

#### handshake\_timeout

Since sing-box 1.14.0

TLS handshake timeout, in golang's Duration format.

`15s` is used by default.

#### certificate\_provider

Since sing-box 1.14.0

Server only

A string or an object.

When string, the tag of a shared [Certificate Provider](/configuration/shared/certificate-provider/).

When object, an inline certificate provider. See [Certificate Provider](/configuration/shared/certificate-provider/) for available types and fields.

## Custom TLS support

QUIC support

Only ECH is supported in QUIC.

#### utls

Client only

Not Recommended

uTLS has had repeated fingerprinting vulnerabilities discovered by researchers.

uTLS is a Go library that attempts to imitate browser TLS fingerprints by copying ClientHello structure. However, browsers use completely different TLS stacks (Chrome uses BoringSSL, Firefox uses NSS) with distinct implementation behaviors that cannot be replicated by simply copying the handshake format, making detection possible. Additionally, the library lacks active maintenance and has poor code quality, making it unsuitable for censorship circumvention.

For TLS fingerprint resistance, use [NaiveProxy](/configuration/inbound/naive/) instead.

uTLS is a fork of "crypto/tls", which provides ClientHello fingerprinting resistance.

Available fingerprint values:

Removed since sing-box 1.10.0

Some legacy chrome fingerprints have been removed and will fallback to chrome:

chrome\_psk
chrome\_psk\_shuffle
chrome\_padding\_psk\_shuffle
chrome\_pq
chrome\_pq\_psk

-   chrome
-   firefox
-   edge
-   safari
-   360
-   qq
-   ios
-   android
-   random
-   randomized

Chrome fingerprint will be used if empty.

### ECH Fields

ECH (Encrypted Client Hello) is a TLS extension that allows a client to encrypt the first part of its ClientHello message.

The ECH key and configuration can be generated by `sing-box generate ech-keypair`.

#### pq\_signature\_schemes\_enabled

Deprecated in sing-box 1.12.0

`pq_signature_schemes_enabled` is deprecated in sing-box 1.12.0 and removed in sing-box 1.13.0.

Enable support for post-quantum peer certificate signature schemes.

#### dynamic\_record\_sizing\_disabled

Deprecated in sing-box 1.12.0

`dynamic_record_sizing_disabled` is deprecated in sing-box 1.12.0 and removed in sing-box 1.13.0.

Disables adaptive sizing of TLS records.

When true, the largest possible TLS record size is always used.
When false, the size of TLS records may be adjusted in an attempt to improve latency.

#### key

Server only

ECH key line array, in PEM format.

#### key\_path

Server only

Will be automatically reloaded if file modified.

The path to ECH key, in PEM format.

#### config

Client only

ECH configuration line array, in PEM format.

If empty, load from DNS will be attempted.

#### config\_path

Client only

The path to ECH configuration, in PEM format.

If empty, load from DNS will be attempted.

#### query\_server\_name

Since sing-box 1.13.0

Client only

Overrides the domain name used for ECH HTTPS record queries.

If empty, `server_name` is used for queries.

#### fragment

Since sing-box 1.12.0

Client only

Fragment TLS handshakes to bypass firewalls.

This feature is intended to circumvent simple firewalls based on **plaintext packet matching**, and should not be used to circumvent real censorship.

Due to poor performance, try `record_fragment` first, and only apply to server names known to be blocked.

On Linux, Apple platforms, (administrator privileges required) Windows, the wait time can be automatically detected. Otherwise, it will fall back to waiting for a fixed time specified by `fragment_fallback_delay`.

In addition, if the actual wait time is less than 20ms, it will also fall back to waiting for a fixed time, because the target is considered to be local or behind a transparent proxy.

#### fragment\_fallback\_delay

Since sing-box 1.12.0

Client only

The fallback value used when TLS segmentation cannot automatically determine the wait time.

`500ms` is used by default.

#### record\_fragment

Since sing-box 1.12.0

Client only

Fragment TLS handshake into multiple TLS records to bypass firewalls.

#### spoof

Since sing-box 1.14.0

Client only, Linux/macOS/Windows only, requires elevated privileges

Inject a forged TLS ClientHello carrying a whitelisted SNI before the real one, to fool SNI-filtering middleboxes that permit specific hostnames.

The forged segment is a copy of the real ClientHello with only the SNI value replaced by the value of this field, so TLS fingerprinting cannot distinguish it from the real one. The receiving server drops the forged segment (see `spoof_method`) while the middlebox treats it as a legitimate session.

Requires raw-socket access (`CAP_NET_RAW` on Linux, root on macOS); on Linux, `CAP_NET_ADMIN` is additionally required because the send sequence number is read via `TCP_REPAIR`. On Windows, Administrator is required to install the embedded WinDivert kernel driver on first use. Windows on ARM64 is not supported.

#### spoof\_method

Since sing-box 1.14.0

Client only

How the forged segment is rejected by the real server.

Value

Behavior

`wrong-sequence` (default)

The forged segment's TCP sequence number is placed before the server's receive window.

`wrong-checksum`

The forged segment's TCP checksum is deliberately invalid.

Conflict with `spoof` unset.

### ACME Fields

Deprecated in sing-box 1.14.0

Inline ACME options are deprecated in sing-box 1.14.0 and will be removed in sing-box 1.16.0, check [Migration](/migration/#migrate-inline-acme-to-certificate-provider).

#### domain

List of domain.

ACME will be disabled if empty.

#### data\_directory

The directory to store ACME data.

`$XDG_DATA_HOME/certmagic|$HOME/.local/share/certmagic` will be used if empty.

#### default\_server\_name

Server name to use when choosing a certificate if the ClientHello's ServerName field is empty.

#### email

The email address to use when creating or selecting an existing ACME server account

#### provider

The ACME CA provider to use.

Value

Provider

`letsencrypt (default)`

Let's Encrypt

`zerossl`

ZeroSSL

`https://...`

Custom

#### disable\_http\_challenge

Disable all HTTP challenges.

#### disable\_tls\_alpn\_challenge

Disable all TLS-ALPN challenges

#### alternative\_http\_port

The alternate port to use for the ACME HTTP challenge; if non-empty, this port will be used instead of 80 to spin up a listener for the HTTP challenge.

#### alternative\_tls\_port

The alternate port to use for the ACME TLS-ALPN challenge; the system must forward 443 to this port for challenge to succeed.

#### external\_account

EAB (External Account Binding) contains information necessary to bind or map an ACME account to some other account known by the CA.

External account bindings are "used to associate an ACME account with an existing account in a non-ACME system, such as a CA customer database.

To enable ACME account binding, the CA operating the ACME server needs to provide the ACME client with a MAC key and a key identifier, using some mechanism outside of ACME. §7.3.4

#### external\_account.key\_id

The key identifier.

#### external\_account.mac\_key

The MAC key.

#### dns01\_challenge

ACME DNS01 challenge field. If configured, other challenge methods will be disabled.

See [DNS01 Challenge Fields](/configuration/shared/dns01_challenge/) for details.

### Reality Fields

#### handshake

Server only

Required

Handshake server address and [Dial Fields](/configuration/shared/dial/).

#### private\_key

Server only

Required

Private key, generated by `sing-box generate reality-keypair`.

#### public\_key

Client only

Required

Public key, generated by `sing-box generate reality-keypair`.

#### short\_id

Required

A hexadecimal string with zero to eight digits.

#### max\_time\_difference

Server only

The maximum time difference between the server and the client.

Check disabled if empty.
