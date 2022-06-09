FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential libreadline-dev autoconf-archive libgmp-dev expect flex bison automake m4 libtool pkg-config libffi-dev

ADD . /bic
WORKDIR /bic
RUN autoreconf -i
RUN ./configure --enable-debug
RUN make -j8

RUN mkdir -p /deps
RUN ldd /bic/src/genaccess | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /bic/src/genaccess /bic/src/genaccess
ENV LD_LIBRARY_PATH=/deps
