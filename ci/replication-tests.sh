#!/usr/bin/env bash
# Builds and runs the replication protocol unit tests without JBoss, GWT,
# jUDDI or the Fénix Framework.
#
# It generates the JAX-WS client classes from anacom.wsdl with the JDK's own
# wsimport (instead of JBoss wsconsume), compiles only the replication code,
# and runs the tests with JUnit.
#
# Requires JDK 8 (wsimport was removed from the JDK in Java 11) and curl.
# Usage: ci/replication-tests.sh
set -euo pipefail

cd "$(dirname "$0")/.."

OUT=build/ci
LIB=$OUT/lib
GEN=$OUT/generated
CLASSES=$OUT/classes
TEST_CLASSES=$OUT/test-classes

MAVEN=https://repo1.maven.org/maven2
DEPS=(
  "junit/junit/4.13.2/junit-4.13.2.jar"
  "org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar"
  "joda-time/joda-time/2.12.7/joda-time-2.12.7.jar"
)

MAIN_SOURCES=(
  src/main/java/anacom/presentationserver/server/replication/GenericComparator.java
  src/main/java/anacom/presentationserver/server/replication/TimestampMaster.java
  src/main/java/anacom/presentationserver/server/replication/protocols/FailureTolerator.java
  src/main/java/anacom/presentationserver/server/replication/protocols/SilentFailureTolerator.java
  src/main/java/anacom/presentationserver/server/replication/protocols/ByzantineFailureTolerator.java
)

TEST_DIR=src/test/java/anacom/replication/test
TEST_SOURCES=(
  $TEST_DIR/AnacomReplicationTestCase.java
  $TEST_DIR/ReplicationProtocolTestCase.java
  $TEST_DIR/GenericComparatorTestCase.java
  $TEST_DIR/TimestampMasterTestCase.java
  $TEST_DIR/SilentFailureProtocolTestCase.java
  $TEST_DIR/ByzantineFailureProtocolTestCase.java
)

TESTS=(
  anacom.replication.test.GenericComparatorTestCase
  anacom.replication.test.TimestampMasterTestCase
  anacom.replication.test.SilentFailureProtocolTestCase
  anacom.replication.test.ByzantineFailureProtocolTestCase
)

rm -rf "$GEN" "$CLASSES" "$TEST_CLASSES"
mkdir -p "$LIB" "$GEN" "$CLASSES" "$TEST_CLASSES"

echo "==> Fetching dependencies"
CP=""
for dep in "${DEPS[@]}"; do
  jar="$LIB/$(basename "$dep")"
  [ -f "$jar" ] || curl -fsSL "$MAVEN/$dep" -o "$jar"
  CP="$CP:$jar"
done
CP=${CP#:}

echo "==> Generating web service client classes from anacom.wsdl"
wsimport -quiet -Xnocompile -keep \
  -p anacom.shared.stubs.client \
  -b ci/async.binding \
  -s "$GEN" \
  src/main/webas/anacom.wsdl

echo "==> Compiling replication code"
find "$GEN" -name '*.java' > "$OUT/generated-sources.txt"
javac -nowarn -encoding UTF-8 -cp "$CP" -d "$CLASSES" \
  @"$OUT/generated-sources.txt" "${MAIN_SOURCES[@]}"

echo "==> Compiling tests"
javac -nowarn -encoding UTF-8 -cp "$CP:$CLASSES" -d "$TEST_CLASSES" \
  "${TEST_SOURCES[@]}"

echo "==> Running tests"
java -cp "$CP:$CLASSES:$TEST_CLASSES" org.junit.runner.JUnitCore "${TESTS[@]}"
