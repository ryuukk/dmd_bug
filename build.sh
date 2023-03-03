#!/usr/bin/env bash

set -e

build_dmd() {
	echo "build dmd"
	dmd \
	-debug -g \
	-m64 -vcolumns -betterC -w -i -i=-std -i=-core \
	-Igame \
	-Istuff/ \
	stuff/rt/object.d \
	game/app.d \
	-of=game.exe
}

build_ldc() {
	echo "build ldc"
	ldc2 \
	-d-debug -g \
	-m64 -vcolumns -betterC -w -i -i=-std -i=-core \
	-Igame \
	-Istuff/ \
	stuff/rt/object.d \
	game/app.d \
	-of=game.exe
}

build_dmd_and_link() {
	echo "build dmd and link (2step)"
	dmd \
	-debug -g -c \
	-m64 -vcolumns -betterC -w -i -i=-std -i=-core \
	-Igame \
	-Istuff/ \
	stuff/rt/object.d \
	game/app.d \
	-of=game.obj

	dmd \
	-debug -g  \
	-m64 -vcolumns -betterC -w -i -i=-std -i=-core \
	game.obj \
	-of=game.exe
}

rm -f game.obj game.exe game.ilk game.pdb


build_ldc
./game.exe
rm -f game.obj game.exe game.ilk game.pdb
sleep 1

build_dmd_and_link
./game.exe
rm -f game.obj game.exe game.ilk game.pdb
sleep 1

build_dmd
./game.exe
rm -f game.obj game.exe game.ilk game.pdb


