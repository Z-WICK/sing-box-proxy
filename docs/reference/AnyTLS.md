# AnyTLS

> 作者: nekohasekai
> 原文链接: https://sing-box.sagernet.org/configuration/inbound/anytls/

---
# AnyTLS

Since sing-box 1.12.0

### Structure

`[](#__codelineno-0-1){ [](#__codelineno-0-2)  "type": "anytls", [](#__codelineno-0-3)  "tag": "anytls-in", [](#__codelineno-0-4) [](#__codelineno-0-5)  ... // Listen Fields [](#__codelineno-0-6) [](#__codelineno-0-7)  "users": [ [](#__codelineno-0-8)    { [](#__codelineno-0-9)      "name": "sekai", [](#__codelineno-0-10)      "password": "8JCsPssfgS8tiRwiMlhARg==" [](#__codelineno-0-11)    } [](#__codelineno-0-12)  ], [](#__codelineno-0-13)  "padding_scheme": [], [](#__codelineno-0-14)  "tls": {} [](#__codelineno-0-15)}`

### Listen Fields

See [Listen Fields](/configuration/shared/listen/) for details.

### Fields

#### users

Required

AnyTLS users.

#### padding\_scheme

AnyTLS padding scheme line array.

Default padding scheme:

`[](#__codelineno-1-1)[ [](#__codelineno-1-2)  "stop=8", [](#__codelineno-1-3)  "0=30-30", [](#__codelineno-1-4)  "1=100-400", [](#__codelineno-1-5)  "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000", [](#__codelineno-1-6)  "3=9-9,500-1000", [](#__codelineno-1-7)  "4=500-1000", [](#__codelineno-1-8)  "5=500-1000", [](#__codelineno-1-9)  "6=500-1000", [](#__codelineno-1-10)  "7=500-1000" [](#__codelineno-1-11)]`

#### tls

TLS configuration, see [TLS](/configuration/shared/tls/#inbound).
