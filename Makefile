.PHONY: build clean

all: build

WITH_MINISAT=$(shell (which minisat > /dev/null 2>&1 && echo true) || echo false)
WITH_PICOSAT=$(shell (which picosat > /dev/null 2>&1 && echo true) || echo false)
WITH_CRYPTOMINISAT=$(shell (which cryptominisat4_simple > /dev/null 2>&1 && echo true) || echo false)

build:
	ocaml pkg/pkg.ml build \
		--with-minisat $(WITH_MINISAT) \
		--with-picosat $(WITH_PICOSAT) \
		--with-cryptominisat  $(WITH_CRYPTOMINISAT)

clean:
	ocaml pkg/pkg.ml clean

