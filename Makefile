#!/bin/sh

### simple makefile

PREFIX=/usr/local

all: build

build:
	clang -llzma -lxar -I ${PREFIX}/include pbzx.c -o pbzx

install:
	install -Dm755 pbzx ${PREFIX}/bin/pbzx
	ldconfig

clean:
	rm -Rf pbzx

uninstall:
	rm -Rf ${PREFIX}/bin/pbzx


