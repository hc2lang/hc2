ARG TARGET=linux/amd64
FROM --platform=${TARGET} gcc:14 AS build
WORKDIR /hc2
COPY bootstrap/ bootstrap/
COPY src/ src/

RUN sh bootstrap/build.sh /tmp/hc2c-boot

RUN set -eux; \
    SRC=src/hc2; \
    case "$(uname -m)" in \
      aarch64|arm64) ART=bootstrap/hc2c_linux_arm64.s; ASFLAGS="" ;; \
      *)             ART=bootstrap/hc2c_linux_amd64.s; ASFLAGS="--64" ;; \
    esac; \
    /tmp/hc2c-boot -S /tmp/s1.s $SRC; \
    cmp /tmp/s1.s "$ART"; \
    as $ASFLAGS -o /tmp/s1.o /tmp/s1.s; \
    ld -static -o /tmp/hc2c /tmp/s1.o; \
    /tmp/hc2c -S /tmp/s2.s $SRC; \
    cmp /tmp/s1.s /tmp/s2.s; \
    echo "fixpoint: $(wc -c < /tmp/s2.s) bytes, identical to the checked-in artifact"

FROM --platform=${TARGET} gcc:14
LABEL org.opencontainers.image.title="hc2" \
      org.opencontainers.image.description="A memory-safe systems language for the next TempleOS"

ARG TARGET
COPY --from=build /tmp/hc2c /usr/local/lib/hc2/bin/hc2
COPY src/hc2.root /usr/local/lib/hc2/hc2.root
COPY src/str/ /usr/local/lib/hc2/str/
COPY src/fmt/ /usr/local/lib/hc2/fmt/
COPY src/hash/ /usr/local/lib/hc2/hash/
COPY src/sys/ /usr/local/lib/hc2/sys/
COPY src/rt/ /usr/local/lib/hc2/rt/
COPY src/heap/ /usr/local/lib/hc2/heap/
RUN chmod +x /usr/local/lib/hc2/bin/hc2 && \
    ln -s /usr/local/lib/hc2/bin/hc2 /usr/local/bin/hc2

WORKDIR /src
CMD ["hc2", "help"]
