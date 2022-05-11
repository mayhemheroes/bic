FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y vim less man wget tar git gzip unzip make cmake software-properties-common curl 
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential libreadline-dev autoconf-archive libgmp-dev expect flex bison automake m4 libtool pkg-config libffi-dev

ADD . /bic
WORKDIR /bic
RUN autoreconf -i
RUN ./configure --enable-debug
RUN make -j8
