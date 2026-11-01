# quoruns-protocol

Quorum-based replication for a simulated mobile-operator system ("Anacom"), with
signed SOAP messages and a small certificate authority. Built in 2013 as a
university project in distributed systems and software engineering, to learn how
voting protocols behave when replicas crash or lie.

## The idea

Each mobile operator's application server is replicated. The presentation server
sends every request to all replicas at once, collects the asynchronous replies,
and decides on an answer once enough replicas have voted:

| Mode | Failure model | When it decides | How it picks the answer |
| --- | --- | --- | --- |
| Silent | Replicas may crash or stop answering | `n/2 + 1` replies (a majority) | The first reply received |
| Byzantine | Replicas may return wrong or forged answers | `n/2 + 2` replies | The first two replies that match; with only two replicas, the one with the newer timestamp |

Replies carry timestamps (`TimestampMaster`) so replicas can be compared and
reconciled. The voting logic is in
[`replication/protocols`](src/main/java/anacom/presentationserver/server/replication/protocols/),
and the fan-out and reply collection are in
[`ReplicatedCommunication`](src/main/java/anacom/presentationserver/server/replication/ReplicatedCommunication.java).

## Security

- **Certificate authority (`cacert`)**: a separate web service that signs
  certificates, sets their validity period and keeps a list of revoked
  certificates.
- **Signed messages**: SOAP handlers on both sides sign outgoing messages and
  check the signature, certificate and revocation status of incoming ones
  (`SecurityHandler`, `AppSecurityHandler`).
- **Replay and ordering protection**: packet-number handlers
  (`PacketNumberHandler`, `PacketOrderHandler`) reject duplicated or
  out-of-order messages.
- **Crypto**: RSA key handling and signatures in
  [`CryptoManager`](src/security/java/security/CryptoManager.java).

## Layout

```
src/
  main/       Anacom: domain model (phones, calls, SMS), services, web service, GWT front end
  cacert/     Certificate authority web service
  security/   Shared RSA / signing helpers
  test/       JUnit tests for services, replication protocols and the CA
RSAkeys/      Demo key pairs for the CA, the presentation server and five operator replicas
docs/         Project reports (PDF) and the sprint backlog
build.xml     Ant build for Anacom
build-ca.xml  Ant build for the CA
```

The main components:

- **Presentation server**: a GWT web UI. It talks to the application servers
  locally or over SOAP, and finds them through a UDDI registry.
- **Application server**: a JAX-WS web service over a Fénix Framework (DML)
  domain model. One WAR is deployed per operator replica (`ws11`–`ws15` are the
  five replicas of operator 1; `ws2` and `ws3` are single-instance operators).
- **CA**: its own JAX-WS web service.

## Running it

This is a 2013 codebase. It depends on a toolchain of that era: Java 6/7, Ant,
JBoss AS 7, GWT 2.x, jUDDI, the Fénix Framework jars and jMock 2.5.1. Expect to
spend some time rebuilding that environment.

`build.properties` expects these environment variables and sibling directories:

```
GWT_HOME, JBOSS_HOME, JUDDI_HOME   environment variables
../lib, ../lib_JAX-R, ../jmock-2.5.1   jar directories next to this repo
```

Typical flow:

```sh
# Certificate authority
ant -f build-ca.xml deploy

# Operator replicas (repeat for Replic2..5, and Operator2 / Operator3)
ant deploy-Operator1-Replic1

# Presentation server against the remote replicas
ant run-remote-silent       # crash-tolerant quorum
ant run-remote-byzantine    # Byzantine-tolerant quorum
ant run-local               # no replication, in-process application server

# Tests
ant test-ES                 # domain services
ant test-SD                 # replication protocols (needs the UDDI registry)
ant -f build-ca.xml test-CA-XJunit
```

Run `ant -p` (or `ant -f build-ca.xml -p`) to list every target.

## Note on keys

The keys in `RSAkeys/` are throwaway demo keys, committed so the project runs as
is. Do not use them for anything real.
