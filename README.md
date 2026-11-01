# byzantine-quorums

[![tests](https://github.com/alex-quiterio/byzantine-quorums/actions/workflows/tests.yml/badge.svg)](https://github.com/alex-quiterio/byzantine-quorums/actions/workflows/tests.yml)

> *"A distributed system is one in which the failure of a computer you didn't
> even know existed can render your own computer unusable."* (Leslie Lamport)

Five servers walk into a bar. One of them is lying. The bartender only serves
the drink once enough of them agree on the order.

That's this project. It's a simulated mobile operator ("Anacom": phones, calls,
SMS, prepaid balance) whose servers are replicated and have to **vote** on every
answer, with signed SOAP messages and a small homemade certificate authority to
keep everyone honest. It was built in 2013 as a university distributed systems
project, back when SOAP was still an acceptable word in polite company.

## The idea: democracy, but for servers

The presentation server sends every request to all replicas at once, collects
the async replies as they arrive, and calls the election once it has enough
votes:

| Mode | Threat model | Waits for | Picks |
| --- | --- | --- | --- |
| 🤫 **Silent** | Replicas crash, hang, or quietly stop answering | `n/2 + 1` replies (a plain majority) | The first reply. Crashed servers don't lie, they just ghost you |
| 🎭 **Byzantine** | Replicas return wrong or forged answers on purpose | `n/2 + 2` replies | The first two replies that agree. With only two replicas, the one with the newer timestamp wins |

Named after the [Byzantine Generals Problem](https://en.wikipedia.org/wiki/Byzantine_fault),
where some of the generals are traitors and the messengers can't be trusted
either. Basically a group chat.

Every reply carries a timestamp (`TimestampMaster`) so replicas can be compared
and the freshest truth wins. The ballot counting is in
[`replication/protocols`](src/main/java/anacom/presentationserver/server/replication/protocols/),
and the "shout at everyone, then wait" part is in
[`ReplicatedCommunication`](src/main/java/anacom/presentationserver/server/replication/ReplicatedCommunication.java).

## Trust issues (the security bits)

- **A certificate authority (`cacert`)**: its own web service that signs
  certificates, sets how long they're valid, and keeps a naughty list of
  revoked ones. (The API calls revoking "revogating", a gift from Portuguese,
  where it's *revogar*. We kept it. It has character.)
- **Signed messages**: SOAP handlers on both sides sign everything going out and
  check the signature, the certificate and the naughty list on everything coming
  in (`SecurityHandler`, `AppSecurityHandler`).
- **Replay protection**: packet-number handlers (`PacketNumberHandler`,
  `PacketOrderHandler`) drop duplicate and out-of-order messages. Nice try,
  Mallory.
- **Crypto**: RSA keys and signatures in
  [`CryptoManager`](src/security/java/security/CryptoManager.java). No custom
  crypto was invented here, which is the first rule of crypto.

## Map of the territory

```
src/
  main/       Anacom: phones, calls, SMS, services, web service, GWT front end
  cacert/     The certificate authority web service
  security/   Shared RSA / signing helpers
  test/       JUnit tests for services, replication protocols and the CA
RSAkeys/      Key pairs for the CA, the presentation server and five operator replicas
docs/         Project reports (PDF) and the sprint backlog, for the archaeologists
build.xml     Ant build for Anacom
build-ca.xml  Ant build for the CA
```

The cast:

- **Presentation server**: a GWT web UI. It talks to the application servers
  locally or over SOAP and finds them through a UDDI registry (think DNS
  for web services, if DNS needed an XML schema and a support group).
- **Application server**: a JAX-WS web service on top of a Fénix Framework
  (DML) domain model. One WAR per replica: `ws11`–`ws15` are the five replicas
  of operator 1, the ones that have to vote. `ws2` and `ws3` are single-instance
  operators living dangerously.
- **CA**: its own JAX-WS web service, trusting no one.

## Running it (a historical reenactment)

This is a 2013 codebase. To run all of it you'll need the full period-accurate
toolchain: Java 6/7, Ant, JBoss AS 7, GWT 2.x, jUDDI, the Fénix Framework jars
and jMock 2.5.1. Set aside an afternoon, and maybe a small offering.

`build.properties` expects:

```
GWT_HOME, JBOSS_HOME, JUDDI_HOME       environment variables
../lib, ../lib_JAX-R, ../jmock-2.5.1   jar directories next to this repo
```

Then:

```sh
# The certificate authority goes first. Nobody talks without papers.
ant -f build-ca.xml deploy

# Operator replicas (repeat for Replic2..5, and Operator2 / Operator3)
ant deploy-Operator1-Replic1

# Presentation server against the remote replicas
ant run-remote-silent       # tolerates crashes
ant run-remote-byzantine    # tolerates liars
ant run-local               # tolerates nothing, one in-process server

# Tests
ant test-ES                 # domain services
ant test-SD                 # replication protocols (needs the UDDI registry)
ant -f build-ca.xml test-CA-XJunit
```

`ant -p` (or `ant -f build-ca.xml -p`) lists every target.

### The shortcut: CI

The voting logic is the interesting part, and you can test it without bringing
back JBoss. GitHub Actions runs the replication tests (`GenericComparator`,
`TimestampMaster`, and the Silent and Byzantine quorums) on every push to `main`
and on every pull request.
[`ci/replication-tests.sh`](ci/replication-tests.sh) generates the SOAP client
classes with the JDK's `wsimport`, compiles only the replication code and runs
JUnit. No app server needed.

```sh
ci/replication-tests.sh                 # with a JDK 8
# or with no Java 8 on your machine:
docker run --rm -v "$PWD":/w -w /w eclipse-temurin:8-jdk ci/replication-tests.sh
```

And yes, the tests do check the quorum math: change the Silent quorum from
`n/2 + 1` to `n/2` and four of them fail.

## ⚠️ About those keys

Yes, there are private keys in `RSAkeys/`, committed to a public repo, on
purpose, so the project runs out of the box. They're demo keys. Treat them like
a password on a sticky note at a conference: fine for the demo, never for
anything real.
